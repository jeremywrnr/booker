# frozen_string_literal: true

# one parser per browser: chrome keeps bookmarks in json, firefox in sqlite, and
# safari in a binary plist. each turns its own format into Booker::Bookmark
# objects, so Bookmarks itself never has to care which browser it is reading.

require "json"
require "fileutils"
require "open3"

require_relative "output"

using Booker::Colors

module Booker
  module Parsers
    # Abstract base class for bookmark parsers
    class Base
      attr_reader :allurls

      def initialize(file_path, search_term)
        @file_path = file_path
        # escaped, not interpolated: the term comes straight off ARGV, so
        # `booker "c++"` used to raise RegexpError before it ever searched
        @searching = Regexp.new(Regexp.escape(search_term), Regexp::IGNORECASE)
        @allurls = []
      end

      # Abstract method - must be implemented by subclasses
      def parse
        raise NotImplementedError, "Subclasses must implement parse method"
      end

      def results = @allurls

      protected

      def matches_search?(values)
        values.any? { |v| v && @searching.match(v.to_s) }
      end
    end

    # Chrome/Chromium bookmark parser (JSON format)
    class Chrome < Base
      def parse
        begin
          local_bookmarks = JSON.parse(File.read(@file_path))
          @chrome_bookmarks = local_bookmarks["roots"]["bookmark_bar"]["children"]
        rescue
          warn "Warning: ".yel + "Bookmarks file not found or invalid."
          warn "Suggest: ".grn + "booker --install bookmarks"
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
            @allurls.push(Bookmark.new(
              folder: base, title: link["name"], url: link["url"], id: link["id"]
            ))
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
    class Firefox < Base
      def parse
        begin
          require "sqlite3"
        rescue LoadError
          warn "Error: ".red + "sqlite3 gem not installed"
          warn "Run: ".grn + "gem install sqlite3"
          return
        end

        # Copy database to temp file if Firefox is running (to avoid lock).
        # Tempfile.create removes the copy when the block ends, so there is no
        # unlink left to remember in an ensure further down
        if firefox_running?
          require "tempfile"
          Tempfile.create(["places", ".sqlite"]) do |temp|
            temp.close
            FileUtils.cp(@file_path, temp.path)
            query_places(temp.path)
          end
        else
          query_places(@file_path)
        end
      end

      private

      def query_places(db_path)
        # the block form closes the handle for us, on the error path too
        SQLite3::Database.new(db_path) do |db|
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
                folder: folder_path,
                title: row["title"] || "",
                url: row["url"] || "",
                id: row["id"].to_s
              )
            end
          end
        end
      rescue SQLite3::Exception => e
        warn "Error: ".red + "Could not read Firefox bookmarks database"
        warn e.message
      end

      def firefox_running?
        return false unless File.exist?(@file_path)

        # Check for Firefox process
        out, _err, _status = Open3.capture3("pgrep", "-x", "firefox")
        !out.strip.empty?
      rescue
        false
      end
    end

    # Safari bookmark parser (binary plist format)
    class Safari < Base
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
          warn "Warning: ".yel + "Could not parse Safari bookmarks: #{e.message}"
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

        # capture3 hands back the status directly, rather than leaving it in the
        # $? global for the next line to read
        output, _err, status = Open3.capture3("plutil", "-convert", "xml1", "-o", "-", path)
        return output if status.success?

        warn "Warning: ".yel + "Could not read Safari bookmarks file."
        warn "Suggest: ".grn + "grant terminal 'Full Disk Access' in System Settings"
        nil
      rescue Errno::ENOENT
        warn "Warning: ".yel + "Safari bookmarks file not found."
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
          @allurls << Bookmark.new(folder:, title:, url:, id:)
        end
      end
    end
  end
end
