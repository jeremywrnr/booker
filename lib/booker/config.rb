# frozen_string_literal: true

# configuation - which platform we are on, how to open a link, and where the
# bookmarks live

require "yaml"

require_relative "output"

using Booker::Colors

module Booker
  # detect operating system
  module OS
    def self.windows? = RUBY_PLATFORM.match?(/cygwin|mswin|mingw|bccwin|wince|emx/)

    def self.mac? = RUBY_PLATFORM.match?(/darwin/)

    def self.linux? = !(windows? || mac?)
  end

  # return browser (chrome) opening command
  module Browser
    def browse
      if OS.windows?
        # alternatively, start seems to work - probably check if powershell v cygwin?
        '/cygdrive/c/Program\ Files\ \(x86\)/Google/Chrome/Application/chrome.exe '
      elsif OS.mac?
        "open "
      else
        # linux? is defined as "neither of the above", so there is no fourth
        # branch for #browse to fall out of and return nil from
        "xdg-open "
      end
    end

    # what an explicit scheme looks like. #domain and #prep are two halves of
    # one grammar - the first decides an argument is a url, the second decides
    # it already says how to fetch it - so they read the rule from here rather
    # than spelling it out twice and drifting apart
    SCHEME = /[a-z][a-z0-9+.-]*:\/\//i

    # does this argument look like a website rather than a search term? matches
    # anything carrying an explicit scheme, or a bare host with a dot and an
    # alphabetic tld. tab completion inserts real bookmark urls, so every tld has
    # to work here - not just the handful (io|com|net|org|...) we used to list,
    # which sent bookmarks on .dev or .ai off to the search engine instead.
    def domain
      %r{\A(?:#{SCHEME}\S+|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d+)?(?:[/?#]\S*)?)\z}io
    end

    # helper methods
    # only a bare host needs a scheme invented for it. testing for "http"
    # alone sent everything else through the same branch, so a completed
    # chrome://bookmarks/ or file:///... came out as http://chrome://bookmarks/
    def prep(url)
      /\A#{SCHEME}/io.match?(url) ? url : "http://" + url
    end
  end

  # configuration
  class Config
    VALID = [:searcher, :bookmarks, :browser, :picker].freeze
    HOME = ENV.fetch("HOME", "/usr/local/").freeze
    YAMLCONF = (HOME + "/.booker.yml").freeze

    class << self
      # one instance per run. Bookmarks, Picker and the CLI all need the same
      # answers, and building a Config apiece meant parsing the yaml three
      # times, running discovery three times when there is no yaml, and
      # printing the "no config file" warning three times to say it once
      def default = @default ||= new

      # the memo outlives a single example, so the suite drops it between them
      def reset! = @default = nil
    end

    def initialize
      # configure w/ yaml config file, if it exists, and only work out the
      # defaults when there is none. detect_default_bookmarks walks every
      # chrome profile directory, which is a lot of filesystem to touch on the
      # way to answering a question the config file has already answered
      @config = read(YAMLCONF) || {
        browser: "open ",
        searcher: "https://google.com/search?q=",
        bookmarks: detect_default_bookmarks
      }

      # prune bad config keys
      @config.each_key do |k|
        if !VALID.include? k.to_sym
          warn "Failure:".red + " Bad key found in config file: #{k}"
          exit 1
        end
      end
    end

    def detect_default_bookmarks
      # Return ALL available bookmark sources (Chrome, Firefox, Safari)
      all_sources = discover_all_bookmark_sources

      # If we found sources, return them all; otherwise return a default single path
      if all_sources.empty?
        # Fallback to macOS Chrome default for backward compatibility
        HOME + "/Library/Application Support/Google/Chrome/Profile 1/Bookmarks"
      else
        all_sources
      end
    end

    def discover_all_bookmark_sources = Sources.discover

    def read(file)
      # #write emits symbol keys, so they have to be permitted on the way back
      YAML.safe_load_file(file, permitted_classes: [Symbol])
    rescue Errno::ENOENT
      warn "Warning: ".yel +
        "YAML configuration file couldn't be found. Using defaults."
      warn "Suggest: ".grn + "booker --install config"
      false
    rescue Psych::Exception
      # every psych failure means the same thing here - an unusable config we
      # fall back from rather than crash on. rescuing SyntaxError alone let
      # anchors through as an AliasesNotEnabled backtrace, since psych 4
      # stopped allowing aliases by default
      warn "Warning: ".red +
        "YAML configuration file could not be read. Using defaults."
      false
    end

    # used for creating and updating the default configuration
    def write(k = nil, v = nil)
      @config[k] = v unless k.nil? # update users yaml config file
      File.write(YAMLCONF, @config.to_yaml)
    end

    # always an array, so callers never branch on it: configs written before
    # multi-source support hold a single path string
    def bookmarks = Array(@config[:bookmarks])

    def searcher = @config[:searcher]

    # the interactive finder command, as a string with its flags - booker splits
    # it with Shellwords rather than handing it to a shell. nil means "auto
    # detect fzf", which is why it is deliberately absent from the defaults
    # #write generates: a config that names it cannot be read by a booker old
    # enough to predate the key, and #initialize above exits on keys it does not
    # know
    def picker = @config[:picker]
  end

  # where browsers keep their bookmarks. one implementation, shared by the
  # auto-detection Config falls back on and by `booker --install bookmarks`:
  # the installer's job is to show you what auto-detection would find, so a
  # second copy of these paths guarantees it eventually shows something else.
  #
  # nothing here tags a source with its browser - Bookmarks.source_for reads
  # that off the filename, exactly as it does when picking a parser
  module Sources
    CHROME = [
      "/Library/Application Support/Google/Chrome",      # macOS
      "/Library/Application Support/Chromium",           # macOS Chromium
      "/.config/google-chrome",                          # Linux
      "/.config/chromium",                               # Linux Chromium
      "/snap/chromium/common/chromium",                  # Linux (snap)
      "/snap/chromium/current/.config/chromium",         # Linux (snap alt)
      "/AppData/Local/Google/Chrome/User Data"           # Windows
    ].freeze

    FIREFOX = [
      "/.mozilla/firefox",                               # Linux
      "/snap/firefox/common/.mozilla/firefox",           # Linux (snap)
      "/Library/Application Support/Firefox",            # macOS
      "/AppData/Roaming/Mozilla/Firefox"                 # Windows
    ].freeze

    SAFARI = "/Library/Safari/Bookmarks.plist"

    class << self
      def discover = (chrome + firefox + safari).uniq

      # every places.sqlite named by a profiles.ini. any Path= counts, including
      # the one under [Install...] - the "which profile did this install last
      # use" block firefox also writes - which names a profile already listed,
      # hence the uniq
      def profiles(ini_path, base)
        File.readlines(ini_path).filter_map do |line|
          key, value = line.strip.split("=", 2)
          next unless key == "Path" && value

          db = File.join(base, value.strip, "places.sqlite")
          db if File.exist?(db)
        end.uniq
      end

      private

      def chrome
        expand(CHROME).flat_map do |base|
          # one level down, not "**": chrome puts Bookmarks directly inside a
          # profile directory, while the rest of the tree is Cache, Code Cache
          # and Service Worker storage - tens of thousands of files a recursive
          # glob walks to find nothing. the second pattern covers a base that
          # already names a profile.
          #
          # globbing relative to base keeps any glob metacharacter in the path
          # itself - a profile directory named "Chrome [work]", say - from
          # being read as part of the pattern
          Dir.glob(["Bookmarks", "*/Bookmarks"], base: base)
            .map { |relative| File.join(base, relative) }
            .select { |file| File.file?(file) }
        rescue
          # Skip if we can't read this directory
          []
        end
      end

      def firefox
        expand(FIREFOX).flat_map do |base|
          ini = File.join(base, "profiles.ini")
          File.exist?(ini) ? profiles(ini, base) : []
        end
      end

      def safari
        path = Config::HOME + SAFARI
        File.exist?(path) ? [path] : []
      end

      def expand(bases) = bases.map { |b| Config::HOME + b }.select { |b| Dir.exist?(b) }
    end
  end
end
