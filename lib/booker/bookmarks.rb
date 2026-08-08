# grab/parse bookmarks from every configured source, and the two value objects
# the parsers hand back

module Booker
  # Main Bookmarks facade class
  class Bookmarks
    PARSER_SOURCE = {
      Parsers::Chrome => "chrome",
      Parsers::Firefox => "firefox",
      Parsers::Safari => "safari"
    }

    attr_reader :allurls

    def initialize(search_term = "")
      @conf = Config.new
      file_paths = @conf.bookmarks
      @allurls = []
      seen = {}

      loaded_sources = file_paths.count { |p| p && File.exist?(p) }
      @multi_source = loaded_sources > 1

      file_paths.each_with_index do |file_path, source_index|
        next unless file_path && File.exist?(file_path)

        parser_class = detect_parser(file_path)
        source = PARSER_SOURCE[parser_class]
        parser = parser_class.new(file_path, search_term)
        parser.parse

        parser.results.each do |bookmark|
          key = [bookmark.title, bookmark.url]
          next if seen[key]
          seen[key] = true

          @allurls << Bookmark.new(
            bookmark.folder,
            bookmark.title,
            bookmark.url,
            "#{source_index}_#{bookmark.id}",
            source
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

    # machine readable feed for the shell completion scripts - one tab separated
    # id/title/url triple per line. unlike #autocomplete this is never truncated
    # or padded, and never depends on the terminal width: `tput cols` is unreliable inside
    # a completion subshell, and a truncated url would open a broken link.
    def autocomplete_raw
      @allurls.each do |url|
        puts [url.id, display_name(url), url.url.delete("\t\n")].join("\t")
      end
    end

    # clean title for completion, delete anything not allowed in linktitle
    def clean_name(url)
      # Use half terminal width for name to leave room for URL
      display_name(url).window([Term.width / 2, 50].min)
    end

    # "[source] folder | title", with no width applied
    def display_name(url)
      # Clean up folder display (remove leading |, show [root] for top-level).
      # "|" and "|/" are both the top level, and both leave nothing behind once
      # the marker is stripped
      folder = url.folder.gsub(/^\|/, "").chomp("/")
      folder = "[root]" if folder.empty?

      # Format: [source] folder | title (source only when multi-source)
      prefix = (@multi_source && url.source) ? "[#{url.source}] " : ""
      name = prefix + folder + " | " + url.title.gsub(/[^a-z0-9\-\/_ ]/i, "")
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
      max_width = [Term.width / 2 - CODEWIDTH, 50].min
      link[0..max_width]
    end

    # get link (from id number). #each returned @allurls itself when nothing
    # matched, so a bad id reached open_bookmark as an Array and blew up with a
    # TypeError instead of the "bookmark not found" message
    def bookmark_url(id)
      @allurls.find { |url| id == url.id }&.url
    end

    private

    def detect_parser(file_path)
      if file_path&.end_with?(".sqlite")
        Parsers::Firefox
      elsif file_path&.end_with?(".plist")
        Parsers::Safari
      else
        Parsers::Chrome
      end
    end
  end

  # for recursively parsing bookmarks
  class Folder
    include Enumerable

    attr_reader :json, :title
    def initialize(json, title = "|")
      @title = title.gsub(/[:,'"]/, "-").downcase
      @json = json
    end

    # needed for Enumerable - has to yield, otherwise every Enumerable method
    # here sees an empty collection
    def each(&block)
      @json.each(&block)
    end
  end

  # clean bookmark title, set attrs
  class Bookmark
    attr_reader :title, :folder, :url, :id, :source
    def initialize(f, t, u, id, source = nil)
      @title = t.gsub(/[:'"+]/, " ").downcase
      @folder = f
      @url = u
      @id = id
      @source = source
    end
  end
end
