# frozen_string_literal: true

# grab/parse bookmarks from every configured source, and the two value objects
# the parsers hand back
#
# Set needs no require: it has been autoloaded since ruby 3.2, which is the
# floor in the gemspec, and is core from 3.5 on

require_relative "output"

using Booker::Colors

module Booker
  # Main Bookmarks facade class
  class Bookmarks
    # one row per browser: everything booker knows about a bookmark source
    # lives here, so a fourth browser is an entry rather than a hunt through
    # the parser lookup, the installer's labels and its colors.
    #
    # chrome's bookmarks file has no extension, which is why it is the
    # fallback rather than a row #source_for can match on
    BROWSERS = {
      firefox: {parser: Parsers::Firefox, ext: ".sqlite", label: "[Firefox]", color: :blu},
      safari: {parser: Parsers::Safari, ext: ".plist", label: "[Safari]", color: :cyan},
      chrome: {parser: Parsers::Chrome, ext: nil, label: "[Chrome]", color: :yel}
    }.freeze

    # which browser wrote this file, by name. the installer labels sources with
    # it and the parse loop below picks a parser with it, so the two can never
    # disagree about what a path is
    def self.source_for(path)
      BROWSERS.find { |_, b| b[:ext] && path&.end_with?(b[:ext]) }&.first || :chrome
    end

    attr_reader :allurls

    def initialize(search_term = "")
      @conf = Config.default
      @allurls = []
      seen = Set.new

      # stat each configured path once, not once to count them and again to
      # read them. the index is kept: it is the source half of every id
      sources = @conf.bookmarks.each_with_index.select { |p, _| p && File.exist?(p) }
      @multi_source = sources.length > 1

      sources.each do |file_path, source_index|
        source = self.class.source_for(file_path)
        parser = BROWSERS.fetch(source)[:parser].new(file_path, search_term)
        parser.parse

        parser.results.each do |bookmark|
          # add? is nil when the key was already there, so the dedupe check and
          # the record of having seen it are the same call
          next unless seen.add?([bookmark.title, bookmark.url])

          @allurls << Bookmark.new(
            folder: bookmark.folder,
            title: bookmark.title,
            url: bookmark.url,
            id: "#{source_index}_#{bookmark.id}",
            source: source
          )
        end
      end
    end

    # output for zsh autocompetion, print out id, title and cleaned url
    def autocomplete
      @allurls.each do |url|
        name = clean_name(url)
        link = clean_link(url)
        puts url.id + ":" + name + ":" + link
      end
    end

    # one tab separated id/title/url triple per bookmark. unlike #autocomplete
    # these are never truncated or padded, and never depend on the terminal
    # width: `tput cols` is unreliable inside a completion subshell, and a
    # truncated url would open a broken link. shared by the shell completion
    # feed below and by the interactive picker, which want the same three fields
    # tabs and newlines are stripped from every field, not just the url: they
    # are the row and column separators, so one surviving inside a folder name
    # would split that bookmark into two candidates - two lines the picker
    # offers separately, and neither of them openable
    def rows
      @allurls.map do |url|
        [url.id, display_name(url), url.url].map { |f| f.to_s.delete("\t\n") }.join("\t")
      end
    end

    # machine readable feed for the shell completion scripts
    def autocomplete_raw
      rows.each { |row| puts row }
    end

    # clean title for completion, delete anything not allowed in linktitle
    def clean_name(url)
      # Use half terminal width for name to leave room for URL
      display_name(url).window((Term.width / 2).clamp(..50))
    end

    # "[source] folder | title", with no width applied
    def display_name(url)
      # Format: [source] folder | title (source only when multi-source)
      prefix = (@multi_source && url.source) ? "[#{url.source}] " : ""
      name = prefix + url.display_folder + " | " + url.title.gsub(/[^a-z0-9\-\/_ ]/i, "")
      name.squeeze!("-")
      name.squeeze!(" ")
      # a top level bookmark has no folder text, which would otherwise leave a
      # leading space - invisible in the padded #clean_name output, but not in
      # the raw feed the completion scripts read
      name.strip
    end

    # clean link for completion, remove strange things from any linkurls
    def clean_link(url)
      link = url.url.gsub(/[,'"&?].*/, "")
      link.gsub!(/.*:\/+/, "")
      link.delete!(" ")
      # Use half terminal width for URL
      max_width = (Term.width / 2 - CODEWIDTH).clamp(..50)
      link[0..max_width]
    end

    # get link (from id number). #each returned @allurls itself when nothing
    # matched, so a bad id reached open_bookmark as an Array and blew up with a
    # TypeError instead of the "bookmark not found" message
    def bookmark_url(id)
      @allurls.find { |url| id == url.id }&.url
    end
  end

  # for recursively parsing bookmarks
  class Folder
    attr_reader :json, :title

    # the browsers disagree about what punctuation belongs in a folder name, so
    # every parser normalizes through here rather than carrying its own copy of
    # the rule for the levels it builds itself
    def self.normalize(title) = title.gsub(/[:,'"]/, "-").downcase

    def initialize(json, title = "|")
      @title = Folder.normalize(title)
      @json = json
    end
  end

  # one parsed bookmark. the three browsers disagree about what punctuation
  # belongs in a title, so cleaning happens here rather than in each parser.
  # Data.new still accepts positional args, so the parsers could pass either
  Bookmark = Data.define(:folder, :title, :url, :id, :source) do
    def initialize(folder:, title:, url:, id:, source: nil)
      super(folder:, title: title.gsub(/[:'"+]/, " ").downcase, url:, id:, source:)
    end

    # the folder as a reader sees it: no leading marker, no trailing slash, and
    # a name for the top level. "|" and "|/" both mean the top level, and both
    # leave nothing behind once the marker is stripped - the picker feed and
    # the --list table share this rather than each deciding what "top" looks
    # like, which is how the same bookmark ended up rendered two ways
    def display_folder
      stripped = folder.gsub(/^\|/, "").chomp("/")
      stripped.empty? ? "[root]" : stripped
    end

    # ruby 3.2's Data#with copies the members straight across without going back
    # through #initialize, so a title replaced there would keep its punctuation
    # and its case. 3.3 fixed that; this is the same thing spelled out, so the
    # gemspec's ">= 3.2" floor holds rather than being true of everything except
    # this one method
    def with(**changes) = self.class.new(**to_h.merge(changes))
  end
end
