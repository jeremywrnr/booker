# frozen_string_literal: true

# everything behind `booker --install`: shell completion, the config file,
# finding browser bookmarks, and the opt-in safari permission walkthrough

require "find"
require "fileutils"
require "shellwords"
require "open3"

require_relative "output"

using Booker::Colors

module Booker
  class Installer
    include Output

    # shells we ship completion for, and where those scripts live
    SHELLS = %w[zsh bash fish].freeze
    COMPLETIONS_DIR = File.expand_path("../../completions", __dir__).freeze

    # if any of these exist, bash-completion is installed and will autoload our
    # script out of the XDG user directory
    BASH_COMPLETION_MARKERS = [
      "/usr/share/bash-completion/bash_completion",
      "/etc/bash_completion",
      "/usr/local/etc/profile.d/bash_completion.sh",
      "/opt/homebrew/etc/profile.d/bash_completion.sh"
    ].freeze

    def install(args)
      target = args.shift
      exit 0 if target.nil?

      # 'all' expands to the full install list (including opt-in safari)
      if /^all$/i.match?(target)
        args = %w[completion config bookmarks safari] + args
        target = args.shift
      end

      if /comp/i.match?(target) # completion for every shell on this machine
        install_completion
      elsif (shell = SHELLS.find { |s| target.downcase.include?(s) })
        install_completion_for(shell) # completion for one named shell
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

    # install completion for every supported shell present on this machine, so a
    # zsh user who also drops into bash gets both without running install twice
    def install_completion
      found, missing = SHELLS.partition { |shell| shell_present?(shell) }

      if found.empty?
        puts "Warning: ".yel + "no supported shell found (#{SHELLS.join(", ")})"
        return
      end

      found.each { |shell| install_completion_for(shell) }

      puts "Skip: ".yel + "#{missing.join(", ")} not installed" unless missing.empty?
    end

    # every shell in SHELLS has an install_completion_<shell>, so adding a fourth
    # means adding the script, the method, and the SHELLS entry - nothing here
    def install_completion_for(shell)
      send("install_completion_#{shell}")
    end

    def install_completion_zsh
      # check if zsh is even installed for this user - capture3 raises
      # Errno::ENOENT when it is not, same as the backtick this replaces
      begin
        out, _err, _status = Open3.capture3("zsh", "-c", "echo $fpath")
        fpath = out.split(" ")
      rescue
        pexit "Failure: ".red + "zsh is probably not installed, could not find $fpath", 1
      end

      # Try user-writable directories first, then system directories
      user_home = home
      writable_dirs = fpath.select do |fp|
        fp.start_with?(user_home) && File.directory?(fp) && File.writable?(fp)
      end

      # If no user-writable directories, try to create one
      if writable_dirs.empty?
        user_completion_dir = File.join(user_home, ".zsh", "completion")
        begin
          # mkdir_p is happy either way, but saying "Created" every time a
          # developer reinstalls is a small lie about what just happened
          existed = File.directory?(user_completion_dir)
          FileUtils.mkdir_p(user_completion_dir)
          writable_dirs << user_completion_dir
          puts "Created user completion directory: #{user_completion_dir}".yel unless existed

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
          File.write(completion_file, completion_script("_booker"))
          system("zsh", "-c", "autoload -U _booker")
          puts "Success: ".grn + "installed zsh autocompletion in #{fp}"
          success = true
          break
        rescue => e
          # Try next directory silently
        end
      end

      if success
        clear_zsh_compdump
      else
        puts "Warning: ".yel + "Could not install ZSH completion to any directory in $fpath"
        puts "Try manually: ".grn + "mkdir -p ~/.zsh/completion && booker --install zsh"
      end
    end

    # compinit caches what it found in $fpath, so a shell started against an old
    # dump keeps describing the completion booker just replaced. the dump is
    # only a cache - zsh rebuilds it on the next start - so dropping it is how a
    # freshly installed script actually reaches a new shell.
    #
    # nothing here can help the shell you ran this from: zsh autoloads _booker
    # once and keeps that copy for the life of the session, which is why the
    # caller is told to unfunction it
    def clear_zsh_compdump
      base = ENV["ZDOTDIR"] || home
      dumps = Dir.glob(File.join(base, ".zcompdump*"))
      return if dumps.empty?

      dumps.each do |dump|
        File.delete(dump)
      rescue
        # a dump we cannot remove is not worth failing an install over
      end

      puts "Refreshed: ".grn + "zsh completion cache (rebuilds on next shell)"
    end

    # bash-completion (when installed) autoloads from the XDG user directory.
    # Without it there is nothing doing the loading, so fall back to a plain
    # directory plus a source line in ~/.bashrc.
    def install_completion_bash
      autoloaded = bash_completion_present?
      dir = if autoloaded
        File.join(xdg_data_home, "bash-completion", "completions")
      else
        File.join(home, ".bash_completion.d")
      end

      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "booker"), completion_script("booker.bash"))
      puts "Success: ".grn + "installed bash completion in #{dir}"

      # with bash-completion installed there is nothing left to wire up
      unless autoloaded
        append_once(
          File.join(home, ".bashrc"),
          "[ -f ~/.bash_completion.d/booker ] && . ~/.bash_completion.d/booker"
        )
      end

      puts "Run: ".yel + "source ~/.bashrc".cyan + " to activate"
    rescue => e
      puts "Warning: ".yel + "could not install bash completion (#{e.message})"
    end

    # fish autoloads anything in its completions directory, so there is no rc
    # file to edit here
    def install_completion_fish
      dir = File.join(xdg_config_home, "fish", "completions")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "booker.fish"), completion_script("booker.fish"))
      puts "Success: ".grn + "installed fish completion in #{dir}"
      puts "Run: ".yel + "exec fish".cyan + " to activate"
    rescue => e
      puts "Warning: ".yel + "could not install fish completion (#{e.message})"
    end

    # read one of the shipped completion scripts (completions/ sits next to lib/,
    # and is listed in the gemspec so it ships with the gem)
    def completion_script(name)
      File.read(File.join(COMPLETIONS_DIR, name))
    rescue Errno::ENOENT
      pexit "Failure: ".red + "completion script #{name} missing from #{COMPLETIONS_DIR}", 1
    end

    def shell_present?(shell)
      system("sh", "-c", "command -v #{Shellwords.escape(shell)}", out: File::NULL, err: File::NULL)
    end

    def bash_completion_present?
      BASH_COMPLETION_MARKERS.any? { |marker| File.exist?(marker) }
    end

    # append a line to an rc file, but only once - install is expected to be
    # re-runnable without stacking up duplicate lines
    def append_once(rcfile, line)
      if File.exist?(rcfile) && File.read(rcfile).include?(line)
        puts "#{rcfile} already configured".grn
        return
      end

      File.open(rcfile, "a") do |f|
        f.puts "\n# Booker completion"
        f.puts line
      end
      puts "Added completion to #{rcfile}".grn
    end

    def home
      ENV["HOME"] || "/usr/local"
    end

    def xdg_data_home
      ENV["XDG_DATA_HOME"] || File.join(home, ".local", "share")
    end

    def xdg_config_home
      ENV["XDG_CONFIG_HOME"] || File.join(home, ".config")
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
          chrome_home = File.join(ENV["HOME"], f)
          next if !FileTest.directory?(chrome_home)
          Find.find(chrome_home) do |file|
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
          Config.new.write(:bookmarks, selected)
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
            Config.new.write(:bookmarks, all_paths)
            puts "Success: ".grn + "config file updated to search all bookmark sources"
          else
            # User selected single source
            actual_index = selection - 1
            selected = bms[actual_index][:path]
            puts "Selected: ".yel + selected
            Config.new.write(:bookmarks, selected)
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
      Config.new.write
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
end
