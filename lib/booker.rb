# parse booker's command line args
require "yaml"
require "find"
require "json"
require "shellwords"
require "fileutils"
require_relative "bookmarks"
require_relative "config"
require_relative "consts"

# get booker opening command
class Booker
  @version = "1.2.1"
  @@version = @version

  class << self
    attr_reader :version
  end

  include Browser

  def initialize(args)
    parse args
  end

  def parse(args)
    # no args given, show interactive bookmark selector
    show_bookmarks if args.none?

    # if arg starts with hyphen, parse option
    parse_opt args if /^-.*/.match?(args.first)

    # separate bookmark IDs from other args
    bookmark_ids = []
    other_args = []

    args.each do |arg|
      if /^[0-9_]+$/.match?(arg)  # bookmark ID (digits or underscore)
        bookmark_ids << arg
      else
        other_args << arg
      end
    end

    # open all bookmarks first
    unless bookmark_ids.empty?
      open_bookmark bookmark_ids
    end

    # then handle remaining args
    unless other_args.empty?
      if other_args.length == 1 && domain.match(other_args.first)
        # single website URL
        puts "opening website: ".grn + other_args.first
        openweb(prep(other_args.first))
      else
        # search for the rest
        open_search(other_args.join(" ").strip)
      end
    end
  end

  def pexit(msg, sig)
    puts msg
    exit sig
  end

  def helper
    pexit HELP_BANNER, 0
  end

  def version
    pexit @@version, 0
  end

  def openweb(url)
    # Pass URL directly to browser without invoking shell
    # This avoids issues with special characters like parentheses
    browser_cmd = browse.strip

    # Redirect stdout/stderr to suppress GTK warnings
    success = system(browser_cmd, url, out: "/dev/null", err: "/dev/null")

    unless success
      puts "Warning: ".yel + "Failed to open URL (exit code: #{$?.exitstatus})"
    end
  end

  # an array of ints, as bookmark ids
  def open_bookmark(bm)
    id = bm.shift
    url = Bookmarks.new.bookmark_url(id)
    pexit "Failure:".red + " bookmark #{id} not found", 1 if url.nil?
    puts "opening bookmark ".grn + url
    openweb(url)  # No wrap() needed - system() handles it
    open_bookmark bm unless bm.empty?
  end

  def open_search(term)
    puts "searching ".grn + term
    search = BConfig.new.searcher
    term = term.tr(" ", "+")
    openweb(search + term)  # No shell escape needed - it's a URL
  end

  def show_bookmarks
    puts "Bookmarks:".grn + " (usage: booker <id> or booker <search>)"
    puts ""

    bm = Bookmarks.new("")  # Get all bookmarks
    allurls = bm.instance_variable_get(:@allurls)

    if allurls.empty?
      puts "No bookmarks found.".red
      puts "Run: ".yel + "booker --install bookmarks".cyan
      exit 0
    end

    # Calculate responsive column widths
    term_width = `tput cols`.to_i
    term_width = 100 if term_width == 0  # fallback

    id_width = 10
    remaining = term_width - id_width - 3  # 3 spaces between columns

    folder_width = [remaining * 0.20, 15].max.to_i
    title_width = [remaining * 0.30, 20].max.to_i
    url_width = [remaining * 0.50, 30].max.to_i

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

  # parse and execute any command line options
  def parse_opt(args)
    valid_opts = %w[--version -v --install -i --help -h
      --complete -c --bookmark -b --search -s]

    nextarg = args.shift
    errormsg = "Error: ".red + "unrecognized option #{nextarg}"
    pexit errormsg, 1 if !(valid_opts.include? nextarg)

    # forced bookmarking
    if nextarg == "--bookmark" || nextarg == "-b"
      if args.first.nil?
        pexit "Error: ".red + "booker --bookmark expects bookmark id", 1
      else
        open_bookmark args
      end
    end

    # autocompletion
    if nextarg == "--complete" || nextarg == "-c"
      allargs = args.join(" ")
      bm = Bookmarks.new(allargs)
      bm.autocomplete
    end

    # installation
    if nextarg == "--install" || nextarg == "-i"
      if !args.empty?
        install(args)
      else # do everything
        install(%w[completion config bookmarks])
      end
    end

    # forced searching
    if nextarg == "--search" || nextarg == "-s"
      pexit "--search requires an argument", 1 if args.empty?
      allargs = args.join(" ")
      open_search allargs
    end

    # print version information
    version if nextarg == "--version" || nextarg == "-v"

    # needs some help
    helper if nextarg == "--help" || nextarg == "-h"

    exit 0 # dont parse_arg
  end # parse_opt

  def install(args)
    target = args.shift
    exit 0 if target.nil?

    if /comp/i.match?(target) # completion installation
      install_completion
    elsif /book/i.match?(target) # bookmarks installation
      install_bookmarks
    elsif /conf/i.match?(target) # default config file generation
      install_config
    else # unknown argument passed into install
      pexit "Failure: ".red + "unknown installation option (#{target})", 1
    end

    install(args) # recurse til done
  end

  def install_completion
    # check if zsh is even installed for this user
    begin
      fpath = `zsh -c 'echo $fpath'`.split(" ")
    rescue
      pexit "Failure: ".red + "zsh is probably not installed, could not find $fpath", 1
    end

    # Try user-writable directories first, then system directories
    user_home = ENV["HOME"]
    writable_dirs = fpath.select do |fp|
      fp.start_with?(user_home) && File.directory?(fp) && File.writable?(fp)
    end

    # If no user-writable directories, try to create one
    if writable_dirs.empty?
      user_completion_dir = File.join(user_home, ".zsh", "completion")
      begin
        FileUtils.mkdir_p(user_completion_dir)
        writable_dirs << user_completion_dir
        puts "Created user completion directory: #{user_completion_dir}".yel

        # Auto-configure .zshrc if it exists
        zshrc = File.join(user_home, ".zshrc")
        if File.exist?(zshrc)
          zshrc_content = File.read(zshrc)
          if zshrc_content.include?(".zsh/completion")
            puts "~/.zshrc already configured".grn
          else
            File.open(zshrc, "a") do |f|
              f.puts "\n# Booker completion"
              f.puts "fpath=(~/.zsh/completion $fpath)"
              f.puts "autoload -Uz compinit && compinit"
            end
            puts "Added completion to ~/.zshrc".grn
            puts "Run: ".yel + "source ~/.zshrc".cyan + " to activate"
          end
        else
          puts "Add this to your ~/.zshrc: ".yel + "fpath=(~/.zsh/completion $fpath)".cyan
        end
      rescue => e
        # Couldn't create user dir, try system dirs as fallback
      end
    end

    # Try writable directories first, then all directories as fallback
    dirs_to_try = writable_dirs + fpath.reject { |fp| writable_dirs.include?(fp) }

    success = false
    dirs_to_try.each do |fp|
      next unless File.directory?(fp)

      begin
        completion_file = File.join(fp, "_booker")
        File.write(completion_file, COMPLETION)
        system "zsh -c 'autoload -U _booker'"
        puts "Success: ".grn + "installed zsh autocompletion in #{fp}"
        success = true
        break
      rescue => e
        # Try next directory silently
      end
    end

    unless success
      puts "Warning: ".yel + "Could not install ZSH completion to any directory in $fpath"
      puts "Try manually: ".grn + "mkdir -p ~/.zsh/completion && booker --install completion"
    end
  end

  def install_bookmarks
    # locate bookmarks file, show user, write to config?
    puts "searching for chrome and firefox bookmarks..."
    begin
      bms = [] # look for bookmarks with type info

      # Search for Chrome bookmarks
      ["Library/Application Support/Google/Chrome",
        "AppData/Local/Google/Chrome/User Data/Default",
        ".config/chromium/Default",
        ".config/google-chrome/Default",
        "snap/chromium/common/chromium",
        "snap/chromium/current/.config/chromium"].each do |f|
        home = File.join(ENV["HOME"], f)
        next if !FileTest.directory?(home)
        Find.find(home) do |file|
          if /chrom.*bookmarks/i.match?(file)
            bms << {path: file, type: :chrome}
          end
        end
      end

      # Search for Firefox bookmarks
      firefox_paths = [
        ".mozilla/firefox",                                # Linux
        "snap/firefox/common/.mozilla/firefox",           # Linux (snap)
        "Library/Application Support/Firefox",            # macOS
        "AppData/Roaming/Mozilla/Firefox"                 # Windows
      ]

      firefox_paths.each do |f|
        firefox_base = File.join(ENV["HOME"], f)
        next if !FileTest.directory?(firefox_base)

        profiles_ini = File.join(firefox_base, "profiles.ini")
        next if !File.exist?(profiles_ini)

        # Parse profiles.ini to find Firefox profiles
        parse_firefox_profiles(profiles_ini, firefox_base).each do |db_path|
          bms << {path: db_path, type: :firefox}
        end
      end

      if bms.empty? # no bookmarks found
        puts "Failure: ".red + "bookmarks file could not be found."
        raise
      elsif bms.length == 1
        # Auto-select if only one source found
        selected = bms.first[:path]
        type_label = (bms.first[:type] == :chrome) ? "[Chrome]" : "[Firefox]"
        puts "Found bookmark source: #{type_label} #{selected}".yel
        puts "Selected: ".yel + selected
        BConfig.new.write(:bookmarks, selected)
        puts "Success: ".grn + "config file updated with your bookmarks"
      else # have user select a file
        puts "select bookmarks source: "

        # Offer "ALL" as first option if multiple sources found
        puts "0".grn + " - " + "[ALL SOURCES]".cyan + " (search across all browsers)"
        offset = 1

        bms.each_with_index do |bm, i|
          type_label = (bm[:type] == :chrome) ? "[Chrome]".yel : "[Firefox]".blu
          puts (i + offset).to_s.grn + " - " + type_label + " " + bm[:path]
        end

        input = gets
        raise "No input provided" if input.nil?
        selection = input.chomp.to_i

        if selection == 0
          # User selected "ALL" - save array of all paths
          all_paths = bms.map { |bm| bm[:path] }
          puts "Selected: ".yel + "All sources (#{bms.length} bookmark files)"
          BConfig.new.write(:bookmarks, all_paths)
          puts "Success: ".grn + "config file updated to search all bookmark sources"
        else
          # User selected single source
          actual_index = selection - 1
          selected = bms[actual_index][:path]
          puts "Selected: ".yel + selected
          BConfig.new.write(:bookmarks, selected)
          puts "Success: ".grn + "config file updated with your bookmarks"
        end
      end
    rescue => e
      puts e.message
      pexit "Failure: ".red + "could not add bookmarks to config file ~/.booker", 1
    end
  end

  def parse_firefox_profiles(ini_path, firefox_base)
    profiles = []
    current_profile = {}

    File.readlines(ini_path).each do |line|
      line = line.strip

      # New profile section
      if line.start_with?("[Profile")
        # Save previous profile if it had a path
        if current_profile[:path]
          db_path = File.join(firefox_base, current_profile[:path], "places.sqlite")
          profiles << db_path if File.exist?(db_path)
        end
        current_profile = {}

      # Parse key=value pairs
      elsif line.include?("=")
        key, value = line.split("=", 2).map(&:strip)
        current_profile[:path] = value if key == "Path"
        current_profile[:name] = value if key == "Name"
      end
    end

    # Don't forget the last profile
    if current_profile[:path]
      db_path = File.join(firefox_base, current_profile[:path], "places.sqlite")
      profiles << db_path if File.exist?(db_path)
    end

    profiles
  end

  def install_config
    BConfig.new.write
    puts "Success: ".grn + "example config file written to ~/.booker"
  rescue
    pexit "Failure: ".red + "could not write example config file to ~/.booker", 1
  end
end
