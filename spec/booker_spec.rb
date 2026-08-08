# rspec testing of booker
require "spec_helper"

# dont actually open links while testing, just ignore
module Browser
  def browse
    "/bin/true "
  end
end

describe Booker do
  def catch_exit
    yield
  rescue SystemExit
    nil
  end

  def run(str)
    Booker.new(str.split)
  end

  def runblock(str)
    lambda { run(str) }
  end

  it "should exit cleanly when no arguments are given" do
    runblock("").should exit_with_code 0
  end

  it "should refuse unrecognized flags" do
    runblock("-goo?-gaah??").should exit_with_code 1
    runblock("-world -goo?").should exit_with_code 1
    runblock("--hello").should exit_with_code 1
  end

  it "should handle unescaped chars in the url" do
    expect { run("(hi)") }.to output(/searching.*\(hi\)/).to_stdout
    expect { run("    testing spaces  ") }.to output(/searching.*testing\s+spaces/).to_stdout
  end

  %w[--bookmark -b --search -s].each do |opt|
    it "should have at least 1 cli arg for #{opt}" do
      runblock(opt).should exit_with_code 1
    end
  end

  %w[--version -v --help -h --complete -c].each do |opt|
    it "should accept valid option #{opt} without args" do
      runblock(opt).should exit_with_code 0
    end
  end

  it "should print the valid version out" do
    %w[--version -v].each do |opt|
      expect { catch_exit { run(opt) } }.to output(Booker.version).to_stdout
    end
  end

  it "should search when given string arguments" do
    ["testing 123", "hi", "mic check mic-check"].each do |str|
      expect { run(str) }.to output("searching #{str}...\n").to_stdout
    end
  end

  it "should handle multiple bookmark IDs" do
    # Mock the bookmarks to avoid actual file reading
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("1").and_return("http://example1.com")
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("2").and_return("http://example2.com")

    expect { run("1 2") }.to output(/opening bookmark.*example1.*opening bookmark.*example2/m).to_stdout
  end

  it "should separate bookmark IDs from search terms" do
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("123").and_return("http://example.com")

    # Should open bookmark 123 and search for "github"
    expect { run("123 github") }.to output(/opening bookmark.*example.*searching github/m).to_stdout
  end

  it "should handle URLs with special shell characters" do
    # Test URL with parentheses, ampersands, and other shell metacharacters
    special_url = "https://example.com/path?query=(test)&foo=bar#section"
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("999").and_return(special_url)

    # Should open without shell errors
    expect { run("999") }.to output(/opening bookmark.*example\.com/m).to_stdout
    expect { run("999") }.not_to output(/Syntax error|unexpected/m).to_stdout
  end

  it "should handle URLs with parentheses like Gmail filters" do
    # Real-world example: Gmail with filter syntax
    gmail_url = "https://mail.google.com/mail/u/0/#section_query/(in%3Ainbox+OR+label%3A%5Eiim)+is%3Aunread"
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("971").and_return(gmail_url)

    # Should open without shell errors
    expect { run("971") }.to output(/opening bookmark.*mail\.google\.com/m).to_stdout
    expect { run("971") }.not_to output(/Syntax error|unexpected/m).to_stdout
  end
end

describe Bookmarks do
  before do
    @rawjson = JSON.parse(open("./spec/bookmarks.json").read)
    @bookmarks = @rawjson["roots"]["bookmark_bar"]["children"]
  end

  it "parses json files correctly" do
    expect(@rawjson).to_not be_nil
  end

  it "parses bookmarks correctly" do
    expect(@bookmarks).to_not be_nil
  end

  describe "with mock config" do
    before do
      allow_any_instance_of(BConfig).to receive(:bookmarks).and_return(["./spec/bookmarks.json"])
    end

    it "should initialize without errors" do
      expect { Bookmarks.new }.not_to raise_error
    end

    it "should find bookmarks matching search term" do
      bm = Bookmarks.new("chrome")
      expect(bm.instance_variable_get(:@allurls)).not_to be_empty
    end

    it "should return empty array when no matches" do
      bm = Bookmarks.new("zzznonexistentzzzz")
      expect(bm.instance_variable_get(:@allurls)).to be_empty
    end

    it "should handle empty search term" do
      bm = Bookmarks.new("")
      expect(bm.instance_variable_get(:@allurls)).not_to be_empty
    end
  end

  describe "#bookmark_url" do
    before do
      allow_any_instance_of(BConfig).to receive(:bookmarks).and_return(["./spec/bookmarks.json"])
      @bm = Bookmarks.new
    end

    it "should return URL for valid ID" do
      first_bookmark = @bm.instance_variable_get(:@allurls).first
      url = @bm.bookmark_url(first_bookmark.id)
      expect(url).not_to be_nil
      expect(url).to be_a(String)
      expect(url).to match(/^(https?|chrome):\/\//)
    end

    it "should return nil for invalid ID" do
      url = @bm.bookmark_url("99999_nonexistent")
      # The method returns nil implicitly when no match found
      expect(url).to be_nil
    end
  end

  describe "#clean_name" do
    before do
      allow_any_instance_of(BConfig).to receive(:bookmarks).and_return(["./spec/bookmarks.json"])
      @bm = Bookmarks.new
    end

    it "should clean special characters from names" do
      bookmark = Bookmark.new("folder/", "Test: Name!", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      expect(cleaned).not_to include(":")
      expect(cleaned).not_to include("!")
    end

    it "should collapse multiple spaces" do
      bookmark = Bookmark.new("folder/", "Test    Name", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      # The clean_name method collapses multiple spaces before window padding
      expect(cleaned).to include("test name")
    end

    it "should truncate to appropriate width for completion" do
      long_name = "a" * (TERMWIDTH + 100)
      bookmark = Bookmark.new("folder/", long_name, "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      # clean_name uses half terminal width or 50, whichever is smaller
      expected_width = [TERMWIDTH / 2, 50].min
      expect(cleaned.length).to eq(expected_width)
    end

    it "should show [root] for root-level bookmarks" do
      bookmark = Bookmark.new("|/", "Test Bookmark", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      expect(cleaned).to include("[root]")
      expect(cleaned).not_to include("|/")
    end

    it "should clean folder paths by removing leading |" do
      bookmark = Bookmark.new("|work/projects/", "Test", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      expect(cleaned).to include("work/projects")
      expect(cleaned).not_to match(/^\|/)  # Should not start with |
    end

    it "should remove trailing slash from folder paths" do
      bookmark = Bookmark.new("|folder/subfolder/", "Test", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      expect(cleaned).to include("folder/subfolder |")  # No trailing slash before |
    end
  end

  describe "#clean_link" do
    before do
      allow_any_instance_of(BConfig).to receive(:bookmarks).and_return(["./spec/bookmarks.json"])
      @bm = Bookmarks.new
    end

    it "should remove protocol from URLs" do
      bookmark = Bookmark.new("folder/", "Test", "https://example.com/path", "1")
      cleaned = @bm.clean_link(bookmark)
      expect(cleaned).not_to match(/https?:\/\//)
    end

    it "should remove query parameters" do
      bookmark = Bookmark.new("folder/", "Test", "http://example.com?foo=bar&baz=qux", "1")
      cleaned = @bm.clean_link(bookmark)
      expect(cleaned).not_to include("?")
    end

    it "should truncate to appropriate width" do
      long_url = "http://example.com/" + ("a" * 500)
      bookmark = Bookmark.new("folder/", "Test", long_url, "1")
      cleaned = @bm.clean_link(bookmark)
      # Implementation uses [0..TERMWIDTH-CODEWIDTH] which is inclusive, so length can be +1
      expect(cleaned.length).to be <= (TERMWIDTH - CODEWIDTH + 1)
    end
  end

  describe "#autocomplete" do
    before do
      allow_any_instance_of(BConfig).to receive(:bookmarks).and_return(["./spec/bookmarks.json"])
      @bm = Bookmarks.new("")
    end

    it "should output in id:name:link format" do
      output = capture_stdout { @bm.autocomplete }
      lines = output.split("\n")

      lines.each do |line|
        expect(line).to match(/^\d+_\d+:.*:.*$/)  # Format: id:name:link
      end
    end

    it "should show clean folder paths in output" do
      output = capture_stdout { @bm.autocomplete }

      # Should NOT contain the old |/ format at the start of names
      # (Looking for pattern like "0_123: |/" which was the old format)
      expect(output).not_to match(/\d+_\d+: \|\//)

      # Folder paths should be cleaned (no leading | in folder part)
      lines = output.split("\n")
      lines.each do |line|
        if line =~ /^(\d+_\d+):(.+):(.+)$/
          name_part = $2
          # The name part should not start with "|/" anymore
          expect(name_part).not_to match(/^ \|\//)
        end
      end
    end

    it "should output clean folder paths without leading |" do
      output = capture_stdout { @bm.autocomplete }
      lines = output.split("\n")

      lines.each do |line|
        parts = line.split(":")
        name_part = parts[1] if parts.length > 1

        # Name part should not start with |
        expect(name_part).not_to match(/^\|/) if name_part
      end
    end
  end
end

# Helper for capturing stdout
def capture_stdout
  old_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old_stdout
end

describe BookmarkParser do
  describe "parser detection" do
    it "ChromeBookmarkParser should be detected for JSON files" do
      bookmarks = Bookmarks.new
      parser_class = bookmarks.send(:detect_parser, "./spec/bookmarks.json")
      expect(parser_class).to eq(ChromeBookmarkParser)
    end

    it "FirefoxBookmarkParser should be detected for SQLite files" do
      bookmarks = Bookmarks.new
      parser_class = bookmarks.send(:detect_parser, "/path/to/places.sqlite")
      expect(parser_class).to eq(FirefoxBookmarkParser)
    end

    it "SafariBookmarkParser should be detected for plist files" do
      bookmarks = Bookmarks.new
      parser_class = bookmarks.send(:detect_parser, "/path/to/Bookmarks.plist")
      expect(parser_class).to eq(SafariBookmarkParser)
    end

    it "ChromeBookmarkParser should default for unknown files" do
      bookmarks = Bookmarks.new
      parser_class = bookmarks.send(:detect_parser, "/path/to/Bookmarks")
      expect(parser_class).to eq(ChromeBookmarkParser)
    end
  end

  describe ChromeBookmarkParser do
    it "should parse Chrome bookmarks file" do
      parser = ChromeBookmarkParser.new("./spec/bookmarks.json", "")
      parser.parse
      results = parser.results
      expect(results).to be_a(Array)
      expect(results).not_to be_empty
    end

    it "should filter bookmarks by search term" do
      parser = ChromeBookmarkParser.new("./spec/bookmarks.json", "chrome")
      parser.parse
      results = parser.results

      # Should only return bookmarks matching 'chrome'
      matching = results.select do |bm|
        bm.title.match?(/chrome/i) || bm.url.match?(/chrome/i) || bm.folder.match?(/chrome/i)
      end
      expect(matching.length).to eq(results.length)
    end

    it "should handle nonexistent file gracefully" do
      parser = ChromeBookmarkParser.new("/nonexistent/file.json", "")
      expect { parser.parse }.not_to raise_error
      expect(parser.results).to be_empty
    end

    it "should extract bookmark properties correctly" do
      parser = ChromeBookmarkParser.new("./spec/bookmarks.json", "")
      parser.parse
      results = parser.results

      first_bookmark = results.first
      expect(first_bookmark).to respond_to(:title)
      expect(first_bookmark).to respond_to(:url)
      expect(first_bookmark).to respond_to(:folder)
      expect(first_bookmark).to respond_to(:id)
    end

    it "should parse nested folders" do
      parser = ChromeBookmarkParser.new("./spec/bookmarks.json", "")
      parser.parse
      results = parser.results

      # Should find bookmarks in nested folders (indicated by /)
      nested = results.select { |bm| bm.folder.count("/") > 1 }
      expect(nested).not_to be_empty
    end
  end

  describe SafariBookmarkParser do
    let(:fixture) { "./spec/safari_bookmarks.plist" }

    it "should parse Safari bookmarks file" do
      parser = SafariBookmarkParser.new(fixture, "")
      parser.parse
      results = parser.results
      expect(results).to be_a(Array)
      expect(results).not_to be_empty
    end

    it "should filter bookmarks by search term" do
      parser = SafariBookmarkParser.new(fixture, "olympics")
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
      parser = SafariBookmarkParser.new("/nonexistent/Bookmarks.plist", "")
      expect { parser.parse }.not_to raise_error
      expect(parser.results).to be_empty
    end

    it "should extract bookmark properties correctly" do
      parser = SafariBookmarkParser.new(fixture, "")
      parser.parse
      first = parser.results.first

      expect(first).to respond_to(:title)
      expect(first).to respond_to(:url)
      expect(first).to respond_to(:folder)
      expect(first).to respond_to(:id)
      expect(first.url).to match(/^https?:\/\//)
    end

    it "should parse nested folders" do
      parser = SafariBookmarkParser.new(fixture, "")
      parser.parse
      results = parser.results

      # fixture has BookmarksBar/Dev/GitHub — at least one nested entry
      nested = results.select { |bm| bm.folder.count("/") > 1 }
      expect(nested).not_to be_empty
    end

    it "should include the BookmarksBar folder prefix" do
      parser = SafariBookmarkParser.new(fixture, "olympics")
      parser.parse
      bm = parser.results.first
      expect(bm.folder).to include("bookmarksbar")
    end

    it "should use WebBookmarkUUID as the bookmark id" do
      parser = SafariBookmarkParser.new(fixture, "olympics")
      parser.parse
      bm = parser.results.first
      expect(bm.id).to eq("BBBB-0001")
    end
  end

  describe FirefoxBookmarkParser do
    it "should handle missing sqlite3 gem gracefully" do
      # Mock LoadError for sqlite3
      allow_any_instance_of(FirefoxBookmarkParser).to receive(:require).with("sqlite3").and_raise(LoadError)

      parser = FirefoxBookmarkParser.new("/fake/places.sqlite", "")
      expect { parser.parse }.not_to raise_error
      expect(parser.results).to be_empty
    end

    it "should handle nonexistent database file" do
      parser = FirefoxBookmarkParser.new("/nonexistent/places.sqlite", "")
      expect { parser.parse }.not_to raise_error
    end
  end
end

describe BConfig do
  it "bookmarks method should return an array" do
    config = BConfig.new
    result = config.bookmarks
    expect(result).to be_a(Array)
  end

  it "should handle single-path string configs (backward compatibility)" do
    config = BConfig.new
    config.instance_variable_set(:@config, {bookmarks: "/path/to/Bookmarks"})
    result = config.bookmarks
    expect(result).to eq(["/path/to/Bookmarks"])
  end

  it "should handle multi-source array configs" do
    config = BConfig.new
    paths = ["/path/to/Bookmarks", "/path/to/places.sqlite"]
    config.instance_variable_set(:@config, {bookmarks: paths})
    result = config.bookmarks
    expect(result).to eq(paths)
  end

  it "should discover multiple bookmark sources" do
    config = BConfig.new
    sources = config.discover_all_bookmark_sources
    expect(sources).to be_a(Array)
  end

  it "should validate config keys" do
    config = BConfig.new
    config.instance_variable_set(:@config, {bookmarks: "/path", invalid_key: "value"})

    expect { config.send(:initialize) }.to raise_error(SystemExit)
  end

  it "should return searcher URL" do
    config = BConfig.new
    searcher = config.searcher
    expect(searcher).to be_a(String)
    expect(searcher).to match(/^https?:/)
  end

  it "should handle missing config file gracefully" do
    allow(File).to receive(:exist?).and_return(false)
    expect { BConfig.new }.not_to raise_error
  end
end

describe Bookmark do
  it "should initialize with all attributes" do
    bookmark = Bookmark.new("folder/", "Test Title", "http://test.com", "123")
    expect(bookmark.folder).to eq("folder/")
    expect(bookmark.title).to eq("test title")  # lowercase
    expect(bookmark.url).to eq("http://test.com")
    expect(bookmark.id).to eq("123")
  end

  it "should clean special characters from title" do
    bookmark = Bookmark.new("folder/", "Test: 'Title' + More", "http://test.com", "123")
    expect(bookmark.title).not_to include(":")
    expect(bookmark.title).not_to include("'")
    expect(bookmark.title).not_to include("+")
  end

  it "should convert title to lowercase" do
    bookmark = Bookmark.new("folder/", "UPPERCASE TITLE", "http://test.com", "123")
    expect(bookmark.title).to eq("uppercase title")
  end
end

describe Folder do
  it "should initialize with title and json" do
    json_data = [{"name" => "Test", "type" => "url"}]
    folder = Folder.new(json_data, "test/")
    expect(folder.title).to eq("test/")
    expect(folder.json).to eq(json_data)
  end

  it "should clean special characters from title" do
    json_data = []
    folder = Folder.new(json_data, "test:'folder'")
    expect(folder.title).not_to include(":")
    expect(folder.title).not_to include("'")
  end

  it "should convert title to lowercase" do
    json_data = []
    folder = Folder.new(json_data, "UPPERCASE")
    expect(folder.title).to eq("uppercase")
  end

  it "should be enumerable" do
    json_data = [{"name" => "Test1"}, {"name" => "Test2"}]
    folder = Folder.new(json_data, "test/")
    expect(folder).to respond_to(:each)
    expect(folder.to_a.length).to eq(2)
  end
end

describe "String extensions" do
  describe "#window" do
    it "should truncate strings longer than width" do
      str = "a" * 100
      result = str.window(10)
      expect(result.length).to eq(10)
    end

    it "should pad strings shorter than width" do
      str = "hello"
      result = str.window(10)
      expect(result.length).to eq(10)
      expect(result).to match(/hello\s+/)
    end

    it "should handle exact width" do
      str = "hello"
      result = str.window(5)
      expect(result).to eq("hello")
    end
  end

  describe "color methods" do
    it "should add color codes" do
      str = "test"
      expect(str.red).to include("\033[")
      expect(str.grn).to include("\033[")
      expect(str.blu).to include("\033[")
      expect(str.yel).to include("\033[")
      expect(str.cyan).to include("\033[")
    end

    it "should reset color codes" do
      str = "test"
      expect(str.reset).to include("\033[0;0m")
    end

    it "should work on empty strings" do
      expect("".red).to be_a(String)
    end
  end
end

describe "Multi-source bookmarks" do
  describe "with multiple sources" do
    before do
      # Mock multiple bookmark sources
      # Two distinct sources so dedup doesn't collapse the second one
      @sources = ["./spec/bookmarks.json", "./spec/safari_bookmarks.plist"]
      allow_any_instance_of(BConfig).to receive(:bookmarks).and_return(@sources)
    end

    it "should parse from all sources" do
      bm = Bookmarks.new("")
      results = bm.instance_variable_get(:@allurls)
      expect(results).not_to be_empty
    end

    it "should prefix IDs with source index" do
      bm = Bookmarks.new("")
      results = bm.instance_variable_get(:@allurls)

      # Should have IDs like 0_xxx and 1_xxx
      source_0_ids = results.select { |b| b.id.start_with?("0_") }
      source_1_ids = results.select { |b| b.id.start_with?("1_") }

      expect(source_0_ids).not_to be_empty
      expect(source_1_ids).not_to be_empty
    end

    it "should handle source with nonexistent file" do
      allow_any_instance_of(BConfig).to receive(:bookmarks).and_return([
        "./spec/bookmarks.json",
        "/nonexistent/file.json"
      ])

      expect { Bookmarks.new("") }.not_to raise_error
    end
  end

  describe "with single source" do
    before do
      allow_any_instance_of(BConfig).to receive(:bookmarks).and_return(["./spec/bookmarks.json"])
    end

    it "should parse from single source" do
      bm = Bookmarks.new("")
      results = bm.instance_variable_get(:@allurls)
      expect(results).not_to be_empty
    end

    it "should prefix IDs with 0_" do
      bm = Bookmarks.new("")
      results = bm.instance_variable_get(:@allurls)
      expect(results.first.id).to start_with("0_")
    end
  end

  describe "with empty sources" do
    before do
      allow_any_instance_of(BConfig).to receive(:bookmarks).and_return([])
    end

    it "should handle empty source list" do
      expect { Bookmarks.new("") }.not_to raise_error
    end

    it "should return empty results" do
      bm = Bookmarks.new("")
      results = bm.instance_variable_get(:@allurls)
      expect(results).to be_empty
    end
  end
end

describe "Browser module" do
  include Browser

  describe "#browse" do
    it "should return xdg-open on Linux" do
      allow(OS).to receive(:linux?).and_return(true)
      allow(OS).to receive(:mac?).and_return(false)
      allow(OS).to receive(:windows?).and_return(false)
      expect(browse).to eq("xdg-open ")
    end

    it "should return open on macOS" do
      allow(OS).to receive(:linux?).and_return(false)
      allow(OS).to receive(:mac?).and_return(true)
      allow(OS).to receive(:windows?).and_return(false)
      expect(browse).to eq("open ")
    end
  end

  describe "#domain" do
    it "should match valid domains" do
      expect("example.com").to match(domain)
      expect("test.io").to match(domain)
      expect("site.net").to match(domain)
      expect("gov.edu").to match(domain)
    end

    it "should match domains with paths" do
      expect("example.com/path").to match(domain)
    end

    it "should not match invalid domains" do
      expect("notadomain").not_to match(domain)
      expect("test").not_to match(domain)
    end
  end

  describe "#prep" do
    it "should add http:// to URLs without protocol" do
      expect(prep("example.com")).to eq("http://example.com")
    end

    it "should not modify URLs with protocol" do
      expect(prep("http://example.com")).to eq("http://example.com")
      expect(prep("https://example.com")).to eq("https://example.com")
    end
  end

  describe "#wrap" do
    it "should wrap URL in quotes" do
      expect(wrap("example.com")).to eq('"example.com"')
    end
  end
end

describe "Integration tests" do
  before do
    allow_any_instance_of(BConfig).to receive(:bookmarks).and_return(["./spec/bookmarks.json"])
  end

  it "should handle full search workflow" do
    bm = Bookmarks.new("chrome")
    results = bm.instance_variable_get(:@allurls)
    expect(results).not_to be_empty

    first_id = results.first.id
    url = bm.bookmark_url(first_id)
    expect(url).not_to be_nil
  end

  it "should handle autocomplete output" do
    bm = Bookmarks.new("chrome")
    expect { bm.autocomplete }.to output(/\d+_\d+:.*:.*/).to_stdout
  end

  it "should handle case-insensitive search" do
    bm_lower = Bookmarks.new("chrome")
    bm_upper = Bookmarks.new("CHROME")
    bm_mixed = Bookmarks.new("ChRoMe")

    expect(bm_lower.instance_variable_get(:@allurls).length).to eq(bm_upper.instance_variable_get(:@allurls).length)
    expect(bm_lower.instance_variable_get(:@allurls).length).to eq(bm_mixed.instance_variable_get(:@allurls).length)
  end

  it "should search across title, URL, and folder" do
    # Create bookmark with search term in different fields
    bm_title = Bookmarks.new("chrome")  # matches title
    bm_url = Bookmarks.new("http")       # matches URL
    bm_folder = Bookmarks.new("r")       # matches folder names

    expect(bm_title.instance_variable_get(:@allurls)).not_to be_empty
    expect(bm_url.instance_variable_get(:@allurls)).not_to be_empty
    expect(bm_folder.instance_variable_get(:@allurls)).not_to be_empty
  end
end
