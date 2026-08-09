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
    # one grammar - is this a url, does it already say how to fetch it - so both
    # read the rule from here rather than spelling it out twice and drifting
    SCHEME = /[a-z][a-z0-9+.-]*:\/\//i

    # does this argument look like a website rather than a search term? an
    # explicit scheme, or a bare host with a dot and an alphabetic tld. every
    # tld has to work: completion inserts real bookmark urls, and the old
    # (io|com|net|org|...) list sent .dev and .ai off to the search engine
    def domain
      %r{\A(?:#{SCHEME}\S+|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d+)?(?:[/?#]\S*)?)\z}io
    end

    # only a bare host needs a scheme invented for it. testing for "http" alone
    # sent everything else down the same branch, so a completed
    # chrome://bookmarks/ came out as http://chrome://bookmarks/
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
      # one instance per run. Bookmarks, Picker and the CLI want the same
      # answers, and one Config apiece meant parsing the yaml three times,
      # discovering three times, and warning three times to say it once
      def default = @default ||= new

      # the memo outlives a single example, so the suite drops it between them
      def reset! = @default = nil
    end

    def initialize
      # the yaml file if there is one, and only work out the defaults when
      # there is not: discovery walks every chrome profile directory to answer
      # a question the config file has already answered
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
      # every psych failure means the same thing here - an unusable config to
      # fall back from rather than crash on. rescuing SyntaxError alone let
      # anchors through as an AliasesNotEnabled backtrace under psych 4
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

    # the finder command with its flags, split with Shellwords rather than
    # handed to a shell. nil means "auto detect fzf", which is why #write leaves
    # it out of the defaults: #initialize exits on keys it does not know, so a
    # config naming it is unreadable by a booker predating the key
    def picker = @config[:picker]
  end

  # where browsers keep their bookmarks. one implementation, shared by the
  # auto-detection Config falls back on and by `booker --install bookmarks` -
  # the installer's job is to show what auto-detection would find, so a second
  # copy of these paths guarantees it eventually shows something else. nothing
  # here tags a source: Bookmarks.source_for reads that off the filename
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

      # every places.sqlite named by a profiles.ini. any Path= counts, and the
      # [Install...] block firefox also writes names a profile already listed,
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
          # profile directory, and the rest of the tree is Cache and Service
          # Worker storage - tens of thousands of files to walk for nothing. the
          # second pattern covers a base that already names a profile. globbing
          # relative to base keeps a metacharacter in the path itself - a
          # profile named "Chrome [work]", say - out of the pattern
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
