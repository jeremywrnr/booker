# grab/parse bookmarks from json file on computer
require "fileutils"

# get int number of columns in half of screen
def terminal_width
  guess = `tput cols`.to_i
  (guess == 0) ? 100 : guess
end
TERMWIDTH = terminal_width

# compl. color codes space
CODEWIDTH = 16

# add some colors, windowing methods
class String
  def window(width)
    if length >= width
      self[0..width - 1]
    else
      ljust(width)
    end
  end

  def colorize(color, mod)
    "\033[#{mod};#{color};49m#{self}\033[0;0m"
  end

  def reset
    colorize(0, 0)
  end

  def blu
    colorize(34, 0)
  end

  def cyan
    colorize(36, 0)
  end

  def yel
    colorize(33, 0)
  end

  def grn
    colorize(32, 0)
  end

  def red
    colorize(31, 0)
  end
end

# Abstract base class for bookmark parsers
class BookmarkParser
  attr_reader :allurls

  def initialize(file_path, search_term)
    @file_path = file_path
    @searching = /#{search_term}/i
    @allurls = []
  end

  # Abstract method - must be implemented by subclasses
  def parse
    raise NotImplementedError, "Subclasses must implement parse method"
  end

  def results
    @allurls
  end

  protected

  def matches_search?(values)
    values.any? { |v| v && @searching.match(v.to_s) }
  end
end

# Chrome/Chromium bookmark parser (JSON format)
class ChromeBookmarkParser < BookmarkParser
  def parse
    begin
      local_bookmarks = JSON.parse(File.read(@file_path))
      @chrome_bookmarks = local_bookmarks["roots"]["bookmark_bar"]["children"]
    rescue
      puts "Warning: ".yel + "Bookmarks file not found or invalid."
      puts "Suggest: ".grn + "booker --install bookmarks"
      @chrome_bookmarks = []
      return
    end

    parse_recursive
  end

  private

  def parse_recursive(root = nil)
    root = Folder.new(@chrome_bookmarks, "|") if root.nil?

    root.json.each { |x| parse_link(root.title, x) }
    root.json.each { |x| parse_folder(root, x) }
  end

  def parse_link(base, link)
    checking = [base, link["name"], link["url"], link["id"]]
    if matches_search?(checking)
      if link["type"] == "url"
        @allurls.push(Bookmark.new(base, link["name"], link["url"], link["id"]))
      end
    end
  end

  def parse_folder(base, link)
    if link["type"] == "folder"
      title = base.title + link["name"] + "/"
      subdir = Folder.new(link["children"], title)
      parse_recursive(subdir)
    end
  end
end

# Firefox bookmark parser (SQLite format)
class FirefoxBookmarkParser < BookmarkParser
  def parse
    begin
      require "sqlite3"
    rescue LoadError
      puts "Error: ".red + "sqlite3 gem not installed"
      puts "Run: ".grn + "gem install sqlite3"
      return
    end

    db_path = @file_path

    # Copy database to temp file if Firefox is running (to avoid lock)
    if firefox_running?
      require "tempfile"
      temp = Tempfile.new(["places", ".sqlite"])
      temp.close
      FileUtils.cp(@file_path, temp.path)
      db_path = temp.path
    end

    begin
      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true

      # Recursive CTE query to build folder paths
      query = <<-SQL
        WITH RECURSIVE bookmark_tree(id, parent, title, url, path) AS (
          -- Start with bookmarks toolbar root
          SELECT b.id, b.parent, b.title, p.url,
                 CAST(b.title as TEXT) as path
          FROM moz_bookmarks b
          LEFT JOIN moz_places p ON b.fk = p.id
          WHERE b.parent = (
            SELECT id FROM moz_bookmarks
            WHERE guid = 'toolbar_____'
          )

          UNION ALL

          -- Recursively get children
          SELECT b.id, b.parent, b.title, p.url,
                 CAST(bt.path || '/' || b.title as TEXT) as path
          FROM moz_bookmarks b
          INNER JOIN bookmark_tree bt ON b.parent = bt.id
          LEFT JOIN moz_places p ON b.fk = p.id
        )
        SELECT id, title, path, url
        FROM bookmark_tree
        WHERE url IS NOT NULL
        ORDER BY path, title
      SQL

      db.execute(query).each do |row|
        folder_path = row["path"].to_s.split("/")[0..-2].join("/") + "/"
        folder_path = "|" + folder_path.gsub(/[:,'"]/, "-").downcase

        values = [folder_path, row["title"], row["url"], row["id"].to_s]
        if matches_search?(values)
          @allurls << Bookmark.new(
            folder_path,
            row["title"] || "",
            row["url"] || "",
            row["id"].to_s
          )
        end
      end
    rescue SQLite3::Exception => e
      puts "Error: ".red + "Could not read Firefox bookmarks database"
      puts e.message
    ensure
      db&.close
      temp&.unlink
    end
  end

  private

  def firefox_running?
    # Simple check - try to get a shared lock
    # If Firefox is running, it has an exclusive lock
    return false unless File.exist?(@file_path)

    begin
      File.open(@file_path, "r") do |f|
        # If we can open for reading, Firefox might still be running
        # but we'll handle it by copying to temp
      end
      # Check for Firefox process
      `pgrep -x firefox 2>/dev/null`.strip != ""
    rescue
      false
    end
  end
end

# Safari bookmark parser (binary plist format)
class SafariBookmarkParser < BookmarkParser
  def parse
    xml = convert_plist_to_xml(@file_path)
    return if xml.nil?

    begin
      require "rexml/document"
      doc = REXML::Document.new(xml)
      plist_el = doc.root
      root_node = plist_el.elements.to_a.first
      root = parse_node(root_node)
    rescue => e
      puts "Warning: ".yel + "Could not parse Safari bookmarks: #{e.message}"
      return
    end

    walk(root, "|")
  end

  private

  def convert_plist_to_xml(path)
    contents = File.read(path)
    # Already an XML plist (fixtures, non-macOS). Binary plists need plutil
    # (macOS-only); the JSON converter rejects <data>/<date> fields, so xml1.
    return contents if contents.start_with?("<?xml") || contents.include?("<plist")

    output = IO.popen(["plutil", "-convert", "xml1", "-o", "-", path], err: File::NULL, &:read)
    return output if $?.success?

    puts "Warning: ".yel + "Could not read Safari bookmarks file."
    puts "Suggest: ".grn + "grant terminal 'Full Disk Access' in System Settings"
    nil
  rescue Errno::ENOENT
    puts "Warning: ".yel + "Safari bookmarks file not found."
    nil
  end

  def parse_node(el)
    case el.name
    when "dict"
      result = {}
      children = el.elements.to_a
      children.each_slice(2) do |key_el, val_el|
        next if key_el.nil? || val_el.nil?
        result[key_el.text.to_s] = parse_node(val_el)
      end
      result
    when "array"
      el.elements.map { |c| parse_node(c) }
    when "string"
      el.text.to_s
    when "integer"
      el.text.to_i
    when "real"
      el.text.to_f
    when "true"
      true
    when "false"
      false
    when "data", "date"
      el.text.to_s
    end
  end

  def walk(node, folder_title)
    children = node["Children"]
    return unless children.is_a?(Array)

    children.each do |child|
      case child["WebBookmarkType"]
      when "WebBookmarkTypeLeaf"
        parse_leaf(folder_title, child)
      when "WebBookmarkTypeList"
        name = child["Title"].to_s
        sub_title = folder_title + name.gsub(/[:,'"]/, "-").downcase + "/"
        walk(child, sub_title)
      end
    end
  end

  def parse_leaf(folder, leaf)
    uri = leaf["URIDictionary"] || {}
    title = (uri["title"] || "").to_s
    url = (leaf["URLString"] || "").to_s
    id = (leaf["WebBookmarkUUID"] || "").to_s

    values = [folder, title, url, id]
    if matches_search?(values)
      @allurls << Bookmark.new(folder, title, url, id)
    end
  end
end

# Main Bookmarks facade class
class Bookmarks
  PARSER_SOURCE = {
    ChromeBookmarkParser => "chrome",
    FirefoxBookmarkParser => "firefox",
    SafariBookmarkParser => "safari"
  }

  def initialize(search_term = "")
    @conf = BConfig.new
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

  # clean title for completion, delete anything not allowed in linktitle
  def clean_name(url)
    # Clean up folder display (remove leading |, show [root] for top-level)
    folder = url.folder.gsub(/^\|/, "")
    folder = (folder == "/") ? "[root]" : folder.chomp("/")

    # Format: [source] folder | title (source only when multi-source)
    prefix = (@multi_source && url.source) ? "[#{url.source}] " : ""
    name = prefix + folder + " | " + url.title.gsub(/[^a-z0-9\-\/_ ]/i, "")
    name.squeeze!("-")
    name.squeeze!(" ")
    # Use half terminal width for name to leave room for URL
    name.window([TERMWIDTH / 2, 50].min)
  end

  # clean link for completion, remove strange things from any linkurls
  def clean_link(url)
    link = url.url.gsub(/[,'"&?].*/, "")
    link.gsub!(/.*:\/+/, "")
    link.delete!(" ")
    # Use half terminal width for URL
    max_width = [TERMWIDTH / 2 - CODEWIDTH, 50].min
    link[0..max_width]
  end

  # get link (from id number)
  def bookmark_url(id)
    @allurls.each do |url|
      return url.url if id == url.id
    end
  end

  private

  def detect_parser(file_path)
    if file_path&.end_with?(".sqlite")
      FirefoxBookmarkParser
    elsif file_path&.end_with?(".plist")
      SafariBookmarkParser
    else
      ChromeBookmarkParser
    end
  end
end # close bookmarks class

# for recursively parsing bookmarks
class Folder
  include Enumerable

  attr_reader :json, :title
  def initialize(json, title = "|")
    @title = title.gsub(/[:,'"]/, "-").downcase
    @json = json
  end

  # needed for Enumerable
  def each
    @json.each
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
