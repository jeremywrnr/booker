# parse booker's command line args
require "yaml"
require "find"
require "json"
require "optparse"
require "shellwords"
require "fileutils"
require_relative "bookmarks"
require_relative "config"
require_relative "consts"

# get booker opening command
class Booker
  @version = "1.3.0"
  @@version = @version

  class << self
    attr_reader :version
  end

  include Browser

  def initialize(args)
    parse args
  end

  def parse(args)
    show_bookmarks if args.none?

    if args.first&.start_with?("-")
      dispatch_option(args)
      exit 0
    end

    bookmark_ids, other_args = args.partition { |a| /^[0-9_]+$/.match?(a) }
    open_bookmark(bookmark_ids) unless bookmark_ids.empty?

    unless other_args.empty?
      if other_args.length == 1 && domain.match(other_args.first)
        puts "opening website: ".grn + other_args.first
        openweb(prep(other_args.first))
      else
        open_search(other_args.join(" ").strip)
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
      opts.separator ""
      opts.separator "Other options:"
      opts.on("-c", "--complete", "show tab completions") { @mode = :complete }
      opts.on("-v", "--version", "print version") {
        puts @@version
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
      args.empty? ? install(%w[completion config bookmarks]) : install(args)
    when :search
      pexit "Error: ".red + "--search requires an argument", 1 if args.empty?
      open_search(args.join(" "))
    when :complete
      Bookmarks.new(args.join(" ")).autocomplete
    end
  rescue OptionParser::InvalidOption => e
    pexit "Error: ".red + e.message, 1
  end

  def pexit(msg, sig)
    puts msg
    exit sig
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

  def install(args)
    target = args.shift
    exit 0 if target.nil?

    # 'all' expands to the full install list (including opt-in safari)
    if /^all$/i.match?(target)
      args = %w[completion config bookmarks safari] + args
      target = args.shift
    end

    if /comp/i.match?(target) # completion installation
      install_completion
    elsif /book/i.match?(target) # bookmarks installation
      install_bookmarks
    elsif /conf/i.match?(target) # default config file generation
      install_config
    elsif /safari/i.match?(target) # opt-in Safari FDA setup (macOS only)
      install_safari
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
    puts "searching for browser bookmarks..."
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

      # Search for Safari bookmarks (macOS only)
      safari_path = File.join(ENV["HOME"], "Library/Safari/Bookmarks.plist")
      bms << {path: safari_path, type: :safari} if File.exist?(safari_path)

      if bms.empty? # no bookmarks found
        puts "Failure: ".red + "bookmarks file could not be found."
        raise
      elsif bms.length == 1
        # Auto-select if only one source found
        selected = bms.first[:path]
        puts "Found bookmark source: #{bookmark_type_label(bms.first[:type])} #{selected}".yel
        puts "Selected: ".yel + selected
        BConfig.new.write(:bookmarks, selected)
        puts "Success: ".grn + "config file updated with your bookmarks"
      else # have user select a file
        puts "select bookmarks source: "

        # Offer "ALL" as first option if multiple sources found
        puts "0".grn + " - " + "[ALL SOURCES]".cyan + " (search across all browsers)"
        offset = 1

        bms.each_with_index do |bm, i|
          puts (i + offset).to_s.grn + " - " + bookmark_type_label(bm[:type], color: true) + " " + bm[:path]
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

  def bookmark_type_label(type, color: false)
    label = {chrome: "[Chrome]", firefox: "[Firefox]", safari: "[Safari]"}[type] || "[?]"
    return label unless color
    case type
    when :chrome then label.yel
    when :firefox then label.blu
    when :safari then label.cyan
    else label
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

  # Opt-in Safari setup: walks through granting Full Disk Access so booker
  # can read ~/Library/Safari/Bookmarks.plist. Not included in the default
  # --install flow because it requires a TCC permission grant.
  def install_safari
    plist = File.join(ENV["HOME"], "Library/Safari/Bookmarks.plist")
    fda_url = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    unless RUBY_PLATFORM.include?("darwin")
      puts "Skip: ".yel + "Safari support is macOS-only."
      return
    end

    unless File.exist?(plist)
      puts "Skip: ".yel + "Safari bookmarks not found at #{plist}"
      puts "Hint: ".grn + "launch Safari at least once, then re-run."
      return
    end

    if safari_readable?(plist)
      puts "PASS: ".grn + "Safari bookmarks are already readable."
      return
    end

    puts "Safari stores bookmarks at:"
    puts "  #{plist}".cyan
    puts
    puts "That file is protected by macOS TCC. Grant Full Disk Access to one of:"
    puts
    puts "  [A] ".cyan + "Your terminal app".yel + " (simplest; inherited by any tool)"
    puts "  [B] ".cyan + "/usr/bin/plutil only".yel + " (narrower scope)"
    puts
    print "Pick [A] or [B] (default A): "
    $stdout.flush
    choice = $stdin.gets.to_s.strip.upcase
    choice = "A" if choice.empty?
    pexit "Error: ".red + "invalid choice.", 1 unless %w[A B].include?(choice)

    puts
    puts "Opening the Full Disk Access pane..."
    system("open", fda_url)
    puts

    puts "In the pane that just opened:"
    if choice == "A"
      puts "  1. Click ".yel + "+".cyan + ", add your terminal app from /Applications"
      puts "  2. Toggle it ".yel + "on".cyan
      puts "  3. ".yel + "Fully quit".cyan + " the terminal (Cmd+Q), reopen it,"
      puts "     and re-run ".yel + "booker --install safari".cyan + " to verify."
    else
      puts "  1. Click ".yel + "+".cyan
      puts "  2. Press ".yel + "Cmd+Shift+G".cyan + " (opens 'Go to Folder')".yel
      puts "  3. Type ".yel + "/usr/bin/plutil".cyan + " and press Return".yel
      puts "  4. Click ".yel + "Open".cyan + ", then toggle it ".yel + "on".cyan
      puts
      print "Press Return once you've added plutil and toggled it on... "
      $stdout.flush
      $stdin.gets

      if safari_readable?(plist)
        puts "PASS: ".grn + "Safari bookmarks are now readable."
      else
        puts "FAIL: ".red + "still can't read the bookmarks file."
        puts "Try fully quitting the terminal (Cmd+Q) and re-running."
      end
    end
  end

  def safari_readable?(plist)
    system("plutil", "-lint", "-s", plist, out: File::NULL, err: File::NULL)
  end
end
