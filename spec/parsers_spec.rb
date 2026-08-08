# specs for the per browser parsers, against the fixtures in spec/fixtures

describe Booker::Parsers::Base do
  describe "parser detection" do
    it "Booker::Parsers::Chrome should be detected for JSON files" do
      bookmarks = Booker::Bookmarks.new
      parser_class = bookmarks.send(:detect_parser, fixture_path("bookmarks.json"))
      expect(parser_class).to eq(Booker::Parsers::Chrome)
    end

    it "Booker::Parsers::Firefox should be detected for SQLite files" do
      bookmarks = Booker::Bookmarks.new
      parser_class = bookmarks.send(:detect_parser, "/path/to/places.sqlite")
      expect(parser_class).to eq(Booker::Parsers::Firefox)
    end

    it "Booker::Parsers::Safari should be detected for plist files" do
      bookmarks = Booker::Bookmarks.new
      parser_class = bookmarks.send(:detect_parser, "/path/to/Bookmarks.plist")
      expect(parser_class).to eq(Booker::Parsers::Safari)
    end

    it "Booker::Parsers::Chrome should default for unknown files" do
      bookmarks = Booker::Bookmarks.new
      parser_class = bookmarks.send(:detect_parser, "/path/to/Bookmarks")
      expect(parser_class).to eq(Booker::Parsers::Chrome)
    end
  end

  describe Booker::Parsers::Chrome do
    it "should parse Chrome bookmarks file" do
      parser = Booker::Parsers::Chrome.new(fixture_path("bookmarks.json"), "")
      parser.parse
      results = parser.results
      expect(results).to be_a(Array)
      expect(results).not_to be_empty
    end

    it "should filter bookmarks by search term" do
      parser = Booker::Parsers::Chrome.new(fixture_path("bookmarks.json"), "chrome")
      parser.parse
      results = parser.results

      # Should only return bookmarks matching 'chrome'
      matching = results.select do |bm|
        bm.title.match?(/chrome/i) || bm.url.match?(/chrome/i) || bm.folder.match?(/chrome/i)
      end
      expect(matching.length).to eq(results.length)
    end

    it "should handle nonexistent file gracefully" do
      parser = Booker::Parsers::Chrome.new("/nonexistent/file.json", "")
      expect { parser.parse }.not_to raise_error
      expect(parser.results).to be_empty
    end

    it "should extract bookmark properties correctly" do
      parser = Booker::Parsers::Chrome.new(fixture_path("bookmarks.json"), "")
      parser.parse
      results = parser.results

      first_bookmark = results.first
      expect(first_bookmark).to respond_to(:title)
      expect(first_bookmark).to respond_to(:url)
      expect(first_bookmark).to respond_to(:folder)
      expect(first_bookmark).to respond_to(:id)
    end

    it "should parse nested folders" do
      parser = Booker::Parsers::Chrome.new(fixture_path("bookmarks.json"), "")
      parser.parse
      results = parser.results

      # Should find bookmarks in nested folders (indicated by /)
      nested = results.select { |bm| bm.folder.count("/") > 1 }
      expect(nested).not_to be_empty
    end
  end

  describe Booker::Parsers::Safari do
    let(:fixture) { fixture_path("safari_bookmarks.plist") }

    it "should parse Safari bookmarks file" do
      parser = Booker::Parsers::Safari.new(fixture, "")
      parser.parse
      results = parser.results
      expect(results).to be_a(Array)
      expect(results).not_to be_empty
    end

    it "should filter bookmarks by search term" do
      parser = Booker::Parsers::Safari.new(fixture, "olympics")
      parser.parse
      results = parser.results

      expect(results).not_to be_empty
      results.each do |bm|
        matches = bm.title.match?(/olympics/i) ||
          bm.url.match?(/olympics/i) ||
          bm.folder.match?(/olympics/i)
        expect(matches).to be true
      end
    end

    it "should handle nonexistent file gracefully" do
      parser = Booker::Parsers::Safari.new("/nonexistent/Bookmarks.plist", "")
      expect { parser.parse }.not_to raise_error
      expect(parser.results).to be_empty
    end

    it "should extract bookmark properties correctly" do
      parser = Booker::Parsers::Safari.new(fixture, "")
      parser.parse
      first = parser.results.first

      expect(first).to respond_to(:title)
      expect(first).to respond_to(:url)
      expect(first).to respond_to(:folder)
      expect(first).to respond_to(:id)
      expect(first.url).to match(/^https?:\/\//)
    end

    it "should parse nested folders" do
      parser = Booker::Parsers::Safari.new(fixture, "")
      parser.parse
      results = parser.results

      # fixture has BookmarksBar/Dev/GitHub — at least one nested entry
      nested = results.select { |bm| bm.folder.count("/") > 1 }
      expect(nested).not_to be_empty
    end

    it "should include the BookmarksBar folder prefix" do
      parser = Booker::Parsers::Safari.new(fixture, "olympics")
      parser.parse
      bm = parser.results.first
      expect(bm.folder).to include("bookmarksbar")
    end

    it "should use WebBookmarkUUID as the bookmark id" do
      parser = Booker::Parsers::Safari.new(fixture, "olympics")
      parser.parse
      bm = parser.results.first
      expect(bm.id).to eq("BBBB-0001")
    end
  end

  describe Booker::Parsers::Firefox do
    it "should handle missing sqlite3 gem gracefully" do
      # Mock LoadError for sqlite3
      allow_any_instance_of(Booker::Parsers::Firefox).to receive(:require).with("sqlite3").and_raise(LoadError)

      parser = Booker::Parsers::Firefox.new("/fake/places.sqlite", "")
      expect { parser.parse }.not_to raise_error
      expect(parser.results).to be_empty
    end

    it "should handle nonexistent database file" do
      parser = Booker::Parsers::Firefox.new("/nonexistent/places.sqlite", "")
      expect { parser.parse }.not_to raise_error
    end
  end
end

describe Booker::Parsers::Firefox do
  # builds the two tables the recursive query walks, so the sqlite path runs
  # anywhere rather than only on a machine with firefox installed
  around do |example|
    Dir.mktmpdir do |tmp|
      @db_path = File.join(tmp, "places.sqlite")
      example.run
    end
  end

  before do
    require "sqlite3"
    db = SQLite3::Database.new(@db_path)
    db.execute_batch(<<~SQL)
      CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT);
      CREATE TABLE moz_bookmarks (
        id INTEGER PRIMARY KEY, parent INTEGER, title TEXT, fk INTEGER, guid TEXT
      );
      INSERT INTO moz_places VALUES (1, 'https://example.com/olympics');
      INSERT INTO moz_bookmarks VALUES (1, 0, 'toolbar', NULL, 'toolbar_____');
      INSERT INTO moz_bookmarks VALUES (2, 1, 'olympics', 1, 'aaaa');
    SQL
    db.close
  end

  def parse(term = "")
    parser = Booker::Parsers::Firefox.new(@db_path, term)
    yield parser if block_given?
    capture_stdout { parser.parse }
    parser.results
  end

  it "reads bookmarks out of a places database" do
    expect(parse.map(&:url)).to include("https://example.com/olympics")
  end

  it "keeps the folder path from the bookmark tree" do
    expect(parse.first.folder).to start_with("|")
  end

  it "filters on the search term" do
    expect(parse("zzznonexistentzzz")).to be_empty
  end

  it "reads from a copy when firefox holds the database open" do
    results = parse { |p| allow(p).to receive(:firefox_running?).and_return(true) }
    expect(results.map(&:url)).to include("https://example.com/olympics")
  end

  it "reports a database it cannot read instead of raising" do
    File.write(@db_path, "this is not a database")
    expect(parse).to be_empty
  end
end

describe "plist scalars" do
  # the fixture only holds strings and dicts; a real Safari file also carries
  # integers, dates and booleans, and parse_node has a branch for each
  it "reads every scalar type a plist can hold" do
    require "rexml/document"
    xml = <<~XML
      <plist version="1.0"><dict>
        <key>s</key><string>hi</string>
        <key>i</key><integer>7</integer>
        <key>r</key><real>1.5</real>
        <key>t</key><true/>
        <key>f</key><false/>
        <key>d</key><date>2026-01-01T00:00:00Z</date>
      </dict></plist>
    XML

    root = REXML::Document.new(xml).root.elements.to_a.first
    parsed = Booker::Parsers::Safari.new("/nonexistent", "").send(:parse_node, root)

    expect(parsed).to eq({
      "s" => "hi", "i" => 7, "r" => 1.5,
      "t" => true, "f" => false, "d" => "2026-01-01T00:00:00Z"
    })
  end

  it "reaches for plutil when the file is not already xml" do
    Dir.mktmpdir do |tmp|
      binary = File.join(tmp, "Bookmarks.plist")
      File.write(binary, "bplist00\x00\x01")

      parser = Booker::Parsers::Safari.new(binary, "")
      output = capture_stdout { parser.parse }

      # plutil fails on a mac and is missing on linux; either way it warns
      expect(output).to match(/Could not read Safari bookmarks|bookmarks file not found/)
      expect(parser.results).to be_empty
    end
  end
end
