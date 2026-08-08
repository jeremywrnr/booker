# frozen_string_literal: true

# parse booker's command line args and act on them

require "optparse"

require_relative "output"

using Booker::Colors

module Booker
  class CLI
    include Browser
    include Output

    # a bookmark id is "<source index>_<browser id>". chrome and firefox number
    # their bookmarks, but safari uses a uuid, so an id is a source index
    # followed by anything id-shaped - matching only digits sent every safari
    # bookmark to the search engine instead of opening it. bare digits stay valid
    # for single-source configs written before the source prefix existed.
    #
    # tab completion inserts urls now rather than ids, but ids remain a first
    # class argument: --bookmark takes them, the picker selects by them, and
    # anything scripted against the older completions still works.
    BOOKMARK_ID = /\A(?:\d+_[a-z0-9-]+|[0-9_]+)\z/i

    def initialize(args)
      parse args
    end

    def parse(args)
      show_bookmarks if args.none?

      if args.first&.start_with?("-")
        dispatch_option(args)
        exit 0
      end

      bookmark_ids, other_args = args.partition { |a| BOOKMARK_ID.match?(a) }
      open_bookmark(bookmark_ids) unless bookmark_ids.empty?

      unless other_args.empty?
        # every argument being a url means they all came from tab completion,
        # which inserts one per bookmark - open the lot. a single non-url word
        # among them makes the whole line a search again, so a phrase that
        # happens to contain a domain still reaches the search engine
        if other_args.all? { |arg| domain.match?(arg) }
          other_args.each do |site|
            puts "opening website: ".grn + site
            openweb(prep(site))
          end
        else
          pick_or_search(other_args.join(" ").strip)
        end
      end
    end

    def option_parser
      @option_parser ||= OptionParser.new do |opts|
        opts.banner = "Usage: booker [options] [arguments]"
        opts.separator ""
        opts.separator "Main options:"
        opts.on("-b", "--bookmark", "explicitly open bookmark") { @mode = :bookmark }
        opts.on("-i", "--install", "install: all|bookmarks|completion|config|safari") { @mode = :install }
        opts.on("-s", "--search", "explicitly search arguments") { @mode = :search }
        opts.on("-l", "--list", "print the bookmark table, skipping the picker") { @mode = :list }
        opts.separator ""
        opts.separator "Other options:"
        opts.on("-c", "--complete", "show tab completions") { @mode = :complete }
        opts.on("--complete-raw", "tab completions, tab separated (for shell scripts)") { @mode = :complete_raw }
        opts.on("-v", "--version", "print version") {
          puts VERSION
          exit 0
        }
        opts.on_tail("-h", "--help", "show help") {
          puts opts
          exit 0
        }
      end
    end

    def dispatch_option(args)
      option_parser.parse!(args)

      case @mode
      when :bookmark
        pexit "Error: ".red + "booker --bookmark expects bookmark id", 1 if args.empty?
        open_bookmark(args)
      when :install
        installer.install(args.empty? ? %w[completion config bookmarks] : args)
      when :search
        pexit "Error: ".red + "--search requires an argument", 1 if args.empty?
        open_search(args.join(" "))
      when :list
        # `booker --list github` narrows the table, rather than silently
        # dropping the term and printing everything
        show_bookmarks(args.join(" "), force_table: true)
      when :complete
        Bookmarks.new(args.join(" ")).autocomplete
      when :complete_raw
        Bookmarks.new(args.join(" ")).autocomplete_raw
      end
    rescue OptionParser::InvalidOption => e
      pexit "Error: ".red + e.message, 1
    end

    def installer
      @installer ||= Installer.new
    end

    def openweb(url)
      # Pass URL directly to browser without invoking shell
      # This avoids issues with special characters like parentheses
      browser_cmd = browse.strip

      # Redirect stdout/stderr to suppress GTK warnings
      success = system(browser_cmd, url, out: File::NULL, err: File::NULL)

      unless success
        # system reports a missing binary as nil rather than false, but the
        # forked child still exited - with 127, the shell convention execvp
        # failures use - so there is a status either way. the &. is only for the
        # case where nothing in this process has spawned a child yet
        code = Process.last_status&.exitstatus
        puts "Warning: ".yel + "Failed to open URL (exit code: #{code})"
      end
    end

    # bookmark ids, opened in order. reading every configured source costs
    # hundreds of milliseconds, so the parsed set is taken as an argument when
    # the caller already has one - the picker does - and looked up once for the
    # whole list rather than once per id, which is what the old recursion did
    def open_bookmark(bm, store = nil)
      store ||= Bookmarks.new

      bm.each do |id|
        url = store.bookmark_url(id)
        pexit "Failure:".red + " bookmark #{id} not found", 1 if url.nil?
        puts "opening bookmark ".grn + url
        openweb(url)  # No wrap() needed - system() handles it
      end
    end

    def open_search(term)
      puts "searching ".grn + term
      search = Config.new.searcher
      term = term.tr(" ", "+")
      openweb(search + term)  # No shell escape needed - it's a URL
    end

    # a term matching bookmarks is offered as a choice; one matching nothing is
    # a search, exactly as it always was - `booker how to use the internet` hits
    # no title, folder or url, so it still reaches the search engine. cancelling
    # the picker is a decision rather than a fallthrough, and `booker -s <term>`
    # is still there to demand the search outright
    def pick_or_search(term)
      if Picker.enabled?
        bookmarks = Bookmarks.new(term)
        pick_and_open(bookmarks) unless bookmarks.allurls.empty?
      end

      open_search(term)
    end

    # offer the bookmarks as a choice and open what comes back. either way this
    # ends the run: cancelling the picker is a decision, not a fallthrough to
    # whatever the caller would have done instead
    def pick_and_open(bookmarks)
      id = Picker.select(bookmarks.rows)
      exit 0 if id.nil?
      open_bookmark([id], bookmarks)
      exit 0
    end

    def show_bookmarks(term = "", force_table: false)
      bookmarks = Bookmarks.new(term)
      allurls = bookmarks.allurls

      if allurls.empty?
        puts "No bookmarks found.".red
        puts "Run: ".yel + "booker --install bookmarks".cyan
        exit 0
      end

      # the picker owns the screen when there is one, so nothing is printed
      # above it. --list forces the table back for anyone who wants it
      pick_and_open(bookmarks) if !force_table && Picker.enabled?

      puts "Bookmarks:".grn + " (usage: booker <id> or booker <search>)"
      puts ""

      # Calculate responsive column widths
      term_width = Term.width

      id_width = 10
      remaining = term_width - id_width - 3  # 3 spaces between columns

      folder_width = (remaining * 0.20).clamp(15..).to_i
      title_width = (remaining * 0.30).clamp(20..).to_i
      url_width = (remaining * 0.50).clamp(30..).to_i

      # Display bookmarks in a readable format
      allurls.each do |bookmark|
        id_str = bookmark.id.to_s.window(id_width).grn

        # Clean up folder display
        folder = bookmark.folder.gsub(/^\|/, "")  # Remove leading |
        folder = (folder == "/") ? "[root]" : folder.chomp("/")  # Show [root] for top-level
        folder_str = folder.window(folder_width).blu

        title_str = bookmark.title.window(title_width).yel
        url_str = bookmark.url.window(url_width)

        puts "#{id_str} #{folder_str} #{title_str} #{url_str}"
      end

      puts ""
      puts "Found #{allurls.length} bookmarks".grn
      puts ""
      puts "Examples:".yel
      puts "  #{"booker #{allurls.first.id}".ljust(20).cyan}  # Open first bookmark"
      puts "  #{"booker github".ljust(20).cyan}  # Search bookmarks for 'github'"
      puts "  #{"booker --help".ljust(20).cyan}  # Show help"

      exit 0
    end
  end
end
