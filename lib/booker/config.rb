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
      %r{\A(?:#{SCHEME}\S+|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d+)?(?:[/?#]\S*)?)\z}i
    end

    # helper methods
    # only a bare host needs a scheme invented for it. testing for "http"
    # alone sent everything else through the same branch, so a completed
    # chrome://bookmarks/ or file:///... came out as http://chrome://bookmarks/
    def prep(url)
      /\A#{SCHEME}/i.match?(url) ? url : "http://" + url
    end

    def wrap(url)
      "\"#{url}\""
    end
  end

  # configuration
  class Config
    VALID = [:searcher, :bookmarks, :browser, :picker].freeze
    HOME = ENV.fetch("HOME", "/usr/local/").freeze
    YAMLCONF = (HOME + "/.booker.yml").freeze

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

        # Find all profile directories and their Bookmarks files. globbing
        # relative to base keeps any glob metacharacter in the path itself -
        # a profile directory named "Chrome [work]", say - from being read as
        # part of the pattern
        Dir.glob("**/Bookmarks", base: base).each do |relative|
          bookmark_file = File.join(base, relative)
          sources << bookmark_file if File.file?(bookmark_file)
        end
      rescue
        # Skip if we can't read this directory
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

      safari_path = HOME + "/Library/Safari/Bookmarks.plist"
      sources << safari_path if File.exist?(safari_path)

      sources.uniq
    end

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

    def searcher = @config[:searcher]

    # the interactive finder command, as a string with its flags - booker splits
    # it with Shellwords rather than handing it to a shell. nil means "auto
    # detect fzf", which is why it is deliberately absent from the defaults
    # #write generates: a config that names it cannot be read by a booker old
    # enough to predate the key, and #initialize above exits on keys it does not
    # know
    def picker = @config[:picker]
  end
end
