# frozen_string_literal: true

# specs for the per browser parsers, against the fixtures in spec/fixtures

RSpec.describe Booker::Parsers::Base do
  # Base is abstract: the browser specific work lives in the subclasses, so a
  # subclass that forgets #parse should say so rather than silently do nothing
  it "refuses to parse without a subclass implementation" do
    parser = Booker::Parsers::Base.new("/nonexistent", "")
    expect { parser.parse }.to raise_error(NotImplementedError, /must implement parse/)
  end

  # the parser and the installer's label both come off Bookmarks.source_for, so
  # these check the browser a path is attributed to rather than one of the two
  describe "parser detection" do
    {
      "bookmarks.json" => [:chrome, Booker::Parsers::Chrome],
      "/path/to/places.sqlite" => [:firefox, Booker::Parsers::Firefox],
      "/path/to/Bookmarks.plist" => [:safari, Booker::Parsers::Safari],
      "/path/to/Bookmarks" => [:chrome, Booker::Parsers::Chrome]
    }.each do |path, (source, parser)|
      it "reads #{path} as #{source}" do
        expect(Booker::Bookmarks.source_for(path)).to eq(source)
        expect(Booker::Bookmarks::BROWSERS[source][:parser]).to eq(parser)
      end
    end
  end

  # the search term arrives straight off ARGV, so it gets escaped rather than
  # interpolated - otherwise every regex metacharacter is a crash or a hang
  describe "search terms containing regex metacharacters" do
    it "treats them as literal text instead of raising" do
      ["c++", "(a+)+$", "what?", "a[b", "*"].each do |term|
        expect { Booker::Parsers::Chrome.new(fixture_path("bookmarks.json"), term).parse }
          .not_to raise_error
      end
    end

    it "matches the metacharacters literally" do
      parser = Booker::Parsers::Chrome.new(fixture_path("bookmarks.json"), ".")
      parser.parse
      # "." as a wildcard would match every bookmark; as a literal it only
      # matches the ones whose text actually contains a dot
      expect(parser.results.length).to be < Booker::Parsers::Chrome
        .new(fixture_path("bookmarks.json"), "").tap(&:parse).results.length
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

    # a truncated or corrupt plist still looks like xml to convert_plist_to_xml,
    # so the REXML failure has to be caught here rather than reaching the user
    it "warns instead of raising on a corrupt plist" do
      Dir.mktmpdir do |tmp|
        broken = File.join(tmp, "Bookmarks.plist")
        File.write(broken, "<plist version=\"1.0\"><dict><key>Children</key>")

        parser = Booker::Parsers::Safari.new(broken, "")
        err = nil
        out = capture_stdout { err = capture_stderr { parser.parse } }

        expect(err).to match(/Could not parse Safari bookmarks/)
        expect(out).to eq("")
        expect(parser.results).to be_empty
      end
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

RSpec.describe Booker::Parsers::Firefox do
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

  # pgrep is not installed everywhere - a missing binary means "assume firefox
  # is not holding the file", not a crash halfway through a parse
  it "treats a missing pgrep as firefox not running" do
    parser = Booker::Parsers::Firefox.new(@db_path, "")
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
    expect(parser.send(:firefox_running?)).to be false
  end
end

RSpec.describe "plist scalars" do
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

  # the real plutil is only on a mac, so the "it ran and refused" branch is
  # stubbed - otherwise linux reaches Errno::ENOENT instead and never sees it
  it "points at Full Disk Access when plutil refuses to read the file" do
    Dir.mktmpdir do |tmp|
      binary = File.join(tmp, "Bookmarks.plist")
      File.write(binary, "bplist00\x00\x01")
      status = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3)
        .with("plutil", "-convert", "xml1", "-o", "-", binary)
        .and_return(["", "Operation not permitted", status])

      parser = Booker::Parsers::Safari.new(binary, "")
      err = capture_stderr { parser.parse }

      expect(err).to match(/Could not read Safari bookmarks file/)
      expect(err).to match(/Full Disk Access/)
      expect(parser.results).to be_empty
    end
  end

  it "reaches for plutil when the file is not already xml" do
    Dir.mktmpdir do |tmp|
      binary = File.join(tmp, "Bookmarks.plist")
      File.write(binary, "bplist00\x00\x01")

      parser = Booker::Parsers::Safari.new(binary, "")
      err = nil
      out = capture_stdout { err = capture_stderr { parser.parse } }

      # plutil fails on a mac and is missing on linux; either way it warns
      expect(err).to match(/Could not read Safari bookmarks|bookmarks file not found/)
      # and the warning stays off stdout, which is where --complete-raw writes
      expect(out).to eq("")
      expect(parser.results).to be_empty
    end
  end
end
