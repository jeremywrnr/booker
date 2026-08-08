# rspec testing of booker
require "spec_helper"

# dont actually open links while testing, just ignore. keep the real
# implementation around under another name so the #browse specs below can still
# exercise it - this override is permanent once the file loads
module Browser
  alias_method :real_browse, :browse

  def browse
    "/bin/true "
  end
end

describe Booker do
  def run(str)
    Booker.new(str.split)
  end

  def runblock(str)
    lambda { run(str) }
  end

  # Several flags end in Booker#pexit, and SystemExit is not a StandardError,
  # so letting one escape an example aborts the whole rspec process - and every
  # example after it is silently never run. Use this when asserting on output
  # rather than on the exit code.
  def run!(str)
    run(str)
  rescue SystemExit
    nil
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
    expect { run!("(hi)") }.to output(/searching.*\(hi\)/).to_stdout
    expect { run!("    testing spaces  ") }.to output(/searching.*testing\s+spaces/).to_stdout
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
      expect { run!(opt) }.to output("#{Booker.version}\n").to_stdout
    end
  end

  # "testing 123" is deliberately not here: a numeric argument is a bookmark
  # id, not a search term, which the "separate bookmark IDs" spec below covers
  it "should search when given string arguments" do
    ["hi", "mic check mic-check"].each do |str|
      expect { run!(str) }.to output(/searching.*#{Regexp.escape(str)}/m).to_stdout
    end
  end

  it "should handle multiple bookmark IDs" do
    # Mock the bookmarks to avoid actual file reading
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("1").and_return("http://example1.com")
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("2").and_return("http://example2.com")

    expect { run!("1 2") }.to output(/opening bookmark.*example1.*opening bookmark.*example2/m).to_stdout
  end

  it "should separate bookmark IDs from search terms" do
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("123").and_return("http://example.com")

    # Should open bookmark 123 and search for "github"
    expect { run!("123 github") }.to output(/opening bookmark.*example.*searching.*github/m).to_stdout
  end

  it "should handle URLs with special shell characters" do
    # Test URL with parentheses, ampersands, and other shell metacharacters
    special_url = "https://example.com/path?query=(test)&foo=bar#section"
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("999").and_return(special_url)

    # Should open without shell errors
    expect { run!("999") }.to output(/opening bookmark.*example\.com/m).to_stdout
    expect { run!("999") }.not_to output(/Syntax error|unexpected/m).to_stdout
  end

  it "should handle URLs with parentheses like Gmail filters" do
    # Real-world example: Gmail with filter syntax
    gmail_url = "https://mail.google.com/mail/u/0/#section_query/(in%3Ainbox+OR+label%3A%5Eiim)+is%3Aunread"
    allow_any_instance_of(Bookmarks).to receive(:bookmark_url).with("971").and_return(gmail_url)

    # Should open without shell errors
    expect { run!("971") }.to output(/opening bookmark.*mail\.google\.com/m).to_stdout
    expect { run!("971") }.not_to output(/Syntax error|unexpected/m).to_stdout
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
      long_name = "a" * (Term.width + 100)
      bookmark = Bookmark.new("folder/", long_name, "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      # clean_name uses half terminal width or 50, whichever is smaller
      expected_width = [Term.width / 2, 50].min
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
      # Implementation uses [0..Term.width-CODEWIDTH] which is inclusive, so length can be +1
      expect(cleaned.length).to be <= (Term.width - CODEWIDTH + 1)
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
    # initialize rebuilds @config from the yaml file, so setting @config
    # directly gets overwritten - stub the read instead
    allow(config).to receive(:read).and_return({bookmarks: "/path", invalid_key: "value"})

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
      expect(real_browse).to eq("xdg-open ")
    end

    it "should return open on macOS" do
      allow(OS).to receive(:linux?).and_return(false)
      allow(OS).to receive(:mac?).and_return(true)
      allow(OS).to receive(:windows?).and_return(false)
      expect(real_browse).to eq("open ")
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

    # bash completion inserts real bookmark urls, so every tld has to open
    # rather than fall through to the search engine
    it "should match any tld, not just a fixed list" do
      expect("web.dev").to match(domain)
      expect("claude.ai").to match(domain)
      expect("some.example.sh/path").to match(domain)
    end

    it "should match urls carrying an explicit scheme" do
      expect("https://example.dev/a/b?c=d").to match(domain)
      expect("file:///Users/me/notes.html").to match(domain)
      expect("http://localhost:3000/app").to match(domain)
    end

    it "should still treat plain words as search terms" do
      expect("mic-check").not_to match(domain)
      expect("(hi)").not_to match(domain)
      expect("example.com.").not_to match(domain)
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

describe "shell completion" do
  # Booker#initialize immediately parses argv, so build a bare instance to
  # exercise the install/read helpers on their own
  let(:booker) { Booker.allocate }

  describe "#completion_script" do
    it "ships a script for every supported shell" do
      expect(Booker::SHELLS).to contain_exactly("zsh", "bash", "fish")
    end

    it "reads the zsh script" do
      expect(booker.completion_script("_booker")).to include("#compdef booker")
    end

    it "reads the bash script" do
      expect(booker.completion_script("booker.bash")).to include("complete -F _booker booker")
    end

    it "reads the fish script" do
      expect(booker.completion_script("booker.fish")).to include("complete -c booker")
    end

    it "has every script call the raw feed rather than --complete" do
      Booker::SHELLS.zip(["_booker", "booker.bash", "booker.fish"]).each do |_shell, name|
        expect(booker.completion_script(name)).to include("booker --complete-raw")
      end
    end

    it "exits rather than raising when a script is missing" do
      expect { booker.completion_script("nope.sh") }.to raise_error(SystemExit)
    end
  end

  describe "installing into a clean home" do
    around do |example|
      Dir.mktmpdir do |tmp|
        saved = ENV.to_hash.slice("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME")
        ENV["HOME"] = tmp
        ENV.delete("XDG_DATA_HOME")
        ENV.delete("XDG_CONFIG_HOME")
        @home = tmp
        begin
          example.run
        ensure
          ENV.delete("XDG_DATA_HOME")
          ENV.delete("XDG_CONFIG_HOME")
          saved.each { |k, v| ENV[k] = v }
        end
      end
    end

    it "installs fish completion where fish autoloads it" do
      capture_stdout { booker.install_completion_fish }
      installed = File.join(@home, ".config/fish/completions/booker.fish")
      expect(File.exist?(installed)).to be true
      expect(File.read(installed)).to eq(booker.completion_script("booker.fish"))
    end

    it "installs bash completion into the XDG dir when bash-completion is present" do
      allow(booker).to receive(:bash_completion_present?).and_return(true)
      capture_stdout { booker.install_completion_bash }

      installed = File.join(@home, ".local/share/bash-completion/completions/booker")
      expect(File.exist?(installed)).to be true
      # bash-completion does the loading, so ~/.bashrc is left alone
      expect(File.exist?(File.join(@home, ".bashrc"))).to be false
    end

    it "falls back to sourcing from bashrc when bash-completion is absent" do
      allow(booker).to receive(:bash_completion_present?).and_return(false)
      capture_stdout { booker.install_completion_bash }

      expect(File.exist?(File.join(@home, ".bash_completion.d/booker"))).to be true
      expect(File.read(File.join(@home, ".bashrc"))).to include(".bash_completion.d/booker")
    end

    it "does not stack up duplicate bashrc lines when re-run" do
      allow(booker).to receive(:bash_completion_present?).and_return(false)
      3.times { capture_stdout { booker.install_completion_bash } }

      bashrc = File.read(File.join(@home, ".bashrc"))
      expect(bashrc.scan("# Booker completion").length).to eq(1)
    end

    it "installs zsh completion under a writable fpath dir" do
      capture_stdout { booker.install_completion_zsh }
      expect(File.exist?(File.join(@home, ".zsh/completion/_booker"))).to be true
    end

    it "installs every detected shell at once" do
      allow(booker).to receive(:shell_present?).and_return(true)
      allow(booker).to receive(:bash_completion_present?).and_return(false)
      capture_stdout { booker.install_completion }

      expect(File.exist?(File.join(@home, ".zsh/completion/_booker"))).to be true
      expect(File.exist?(File.join(@home, ".bash_completion.d/booker"))).to be true
      expect(File.exist?(File.join(@home, ".config/fish/completions/booker.fish"))).to be true
    end

    it "skips shells that are not installed instead of failing" do
      allow(booker).to receive(:shell_present?) { |shell| shell == "fish" }
      output = capture_stdout { booker.install_completion }

      expect(File.exist?(File.join(@home, ".config/fish/completions/booker.fish"))).to be true
      expect(output).to match(/Skip.*zsh, bash/)
    end

    it "warns rather than failing when no supported shell exists" do
      allow(booker).to receive(:shell_present?).and_return(false)
      output = capture_stdout { booker.install_completion }
      expect(output).to match(/no supported shell found/)
    end

    %w[zsh bash fish].each do |shell|
      it "routes --install #{shell} to just that shell" do
        expect(booker).to receive(:"install_completion_#{shell}")
        expect { booker.install([shell]) }.to raise_error(SystemExit)
      end
    end
  end
end

describe "#autocomplete_raw" do
  before do
    allow_any_instance_of(BConfig).to receive(:bookmarks).and_return(["./spec/bookmarks.json"])
    @bm = Bookmarks.new
  end

  it "prints one tab separated id, title and url per bookmark" do
    output = capture_stdout { @bm.autocomplete_raw }
    expect(output.lines).not_to be_empty

    output.lines.each do |line|
      expect(line.chomp.split("\t").length).to eq(3)
    end
  end

  it "never truncates the url, unlike #autocomplete" do
    longest = @bm.instance_variable_get(:@allurls).max_by { |u| u.url.length }
    raw = capture_stdout { @bm.autocomplete_raw }

    expect(longest.url.length).to be > 50
    expect(raw).to include(longest.url)
    expect(capture_stdout { @bm.autocomplete }).not_to include(longest.url)
  end

  it "does not pad the title out to the terminal width" do
    output = capture_stdout { @bm.autocomplete_raw }

    output.lines.each do |line|
      title = line.chomp.split("\t")[1]
      expect(title).to eq(title.strip)
    end
  end

  it "emits an id that bookmark_url can resolve" do
    id = capture_stdout { @bm.autocomplete_raw }.lines.first.split("\t").first
    expect(@bm.bookmark_url(id)).to be_a(String)
  end
end
