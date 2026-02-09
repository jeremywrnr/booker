# configuation - get where bookmarks are

# detect operating system
module OS
  def self.windows?
    (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
  end

  def self.mac?
    (/darwin/ =~ RUBY_PLATFORM) != nil
  end

  def self.linux?
    !(OS.windows? or OS.mac?)
  end
end

# return browser (chrome) opening command
module Browser
  extend OS

  def browse
    if OS.windows?
      # alternatively, start seems to work - probably check if powershell v cygwin?
      '/cygdrive/c/Program\ Files\ \(x86\)/Google/Chrome/Application/chrome.exe '
    elsif OS.mac?
      "open "
    elsif OS.linux?
      "xdg-open "
    end
  end

  def domain
    /.*(io|com|web|net|org|gov|edu|xyz)(\/.*)?$/i
  end

  # helper methods
  def prep(url)
    if /^http/.match?(url)
      url
    else
      "http://" + url
    end
  end

  def wrap(url)
    "\"#{url}\""
  end
end

# configuration
class BConfig
  VALID = [:searcher, :bookmarks, :browser]
  HOME = ENV["HOME"].nil? ? "/usr/local/" : ENV["HOME"]
  YAMLCONF = HOME + "/.booker.yml"

  def initialize
    # config defaults (for osx, default chrome profile)
    readyaml = read(YAMLCONF)
    default_bookmarks = detect_default_bookmarks
    default_config = {
      browser: "open ",
      searcher: "https://google.com/search?q=",
      bookmarks: default_bookmarks
    }

    # configure w/ yaml config file, if it exists
    @config = readyaml || default_config

    # prune bad config keys
    @config.each do |k, v|
      if !VALID.include? k.to_sym
        puts "Failure:".red + " Bad key found in config file: #{k}"
        exit 1
      end
    end
  end

  def detect_default_bookmarks
    # Return ALL available bookmark sources (both Chrome and Firefox)
    all_sources = discover_all_bookmark_sources

    # If we found sources, return them all; otherwise return a default single path
    if all_sources.empty?
      # Fallback to macOS Chrome default for backward compatibility
      HOME + "/Library/Application Support/Google/Chrome/Profile 1/Bookmarks"
    else
      all_sources
    end
  end

  def discover_all_bookmark_sources
    sources = []

    # Discover all Chrome/Chromium bookmarks
    chrome_base_paths = [
      HOME + "/Library/Application Support/Google/Chrome",     # macOS
      HOME + "/Library/Application Support/Chromium",          # macOS Chromium
      HOME + "/.config/google-chrome",                         # Linux
      HOME + "/.config/chromium",                              # Linux Chromium
      HOME + "/snap/chromium/common/chromium",                 # Linux (snap)
      HOME + "/snap/chromium/current/.config/chromium",        # Linux (snap alt)
      HOME + "/AppData/Local/Google/Chrome/User Data"         # Windows
    ]

    chrome_base_paths.each do |base|
      next unless Dir.exist?(base)

      # Find all profile directories and their Bookmarks files
      begin
        Dir.glob(File.join(base, "**/Bookmarks")).each do |bookmark_file|
          sources << bookmark_file if File.file?(bookmark_file)
        end
      rescue
        # Skip if we can't read this directory
      end
    end

    # Discover all Firefox profiles
    firefox_base_paths = [
      HOME + "/.mozilla/firefox",                              # Linux
      HOME + "/snap/firefox/common/.mozilla/firefox",         # Linux (snap)
      HOME + "/Library/Application Support/Firefox",          # macOS
      HOME + "/AppData/Roaming/Mozilla/Firefox"              # Windows
    ]

    firefox_base_paths.each do |firefox_base|
      next unless Dir.exist?(firefox_base)

      profiles_ini = File.join(firefox_base, "profiles.ini")
      next unless File.exist?(profiles_ini)

      # Parse all Firefox profiles
      File.readlines(profiles_ini).each do |line|
        if line.include?("Path=")
          profile_path = line.split("=", 2)[1].strip
          db_path = File.join(firefox_base, profile_path, "places.sqlite")
          sources << db_path if File.exist?(db_path)
        end
      end
    end

    sources.uniq
  end

  def read(file)
    begin
      config = YAML.load(IO.read(file))
    rescue Errno::ENOENT
      warn "Warning: ".yel +
        "YAML configuration file couldn't be found. Using defaults."
      warn "Suggest: ".grn + "booker --install config"
      return false
    rescue Psych::SyntaxError
      warn "Warning: ".red +
        "YAML configuration file contains invalid syntax. Using defaults."
      return false
    end
    config
  end

  # used for creating and updating the default configuration
  def write(k = nil, v = nil)
    if k.nil? && v.nil?
    else
      @config[k] = v # update users yaml config file
    end
    File.write(YAMLCONF, @config.to_yaml)
  end

  def bookmarks
    # Return array of bookmark sources
    # Handles both old single-path configs and new multi-source configs
    result = @config[:bookmarks]

    if result.is_a?(Array)
      result
    else
      # Single path - wrap in array for consistent interface
      [result]
    end
  end

  def searcher
    @config[:searcher]
  end
end
