# specs for Booker::Bookmarks and the value objects it hands back

describe Booker::Bookmarks do
  before do
    @rawjson = JSON.parse(File.read(fixture_path("bookmarks.json")))
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
      allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([fixture_path("bookmarks.json")])
    end

    it "should initialize without errors" do
      expect { Booker::Bookmarks.new }.not_to raise_error
    end

    it "should find bookmarks matching search term" do
      bm = Booker::Bookmarks.new("chrome")
      expect(bm.allurls).not_to be_empty
    end

    it "should return empty array when no matches" do
      bm = Booker::Bookmarks.new("zzznonexistentzzzz")
      expect(bm.allurls).to be_empty
    end

    it "should handle empty search term" do
      bm = Booker::Bookmarks.new("")
      expect(bm.allurls).not_to be_empty
    end
  end

  describe "#bookmark_url" do
    before do
      allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([fixture_path("bookmarks.json")])
      @bm = Booker::Bookmarks.new
    end

    it "should return URL for valid ID" do
      first_bookmark = @bm.allurls.first
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
      allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([fixture_path("bookmarks.json")])
      @bm = Booker::Bookmarks.new
    end

    it "should clean special characters from names" do
      bookmark = Booker::Bookmark.new("folder/", "Test: Name!", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      expect(cleaned).not_to include(":")
      expect(cleaned).not_to include("!")
    end

    it "should collapse multiple spaces" do
      bookmark = Booker::Bookmark.new("folder/", "Test    Name", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      # The clean_name method collapses multiple spaces before window padding
      expect(cleaned).to include("test name")
    end

    it "should truncate to appropriate width for completion" do
      long_name = "a" * (Booker::Term.width + 100)
      bookmark = Booker::Bookmark.new("folder/", long_name, "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      # clean_name uses half terminal width or 50, whichever is smaller
      expected_width = [Booker::Term.width / 2, 50].min
      expect(cleaned.length).to eq(expected_width)
    end

    it "should show [root] for root-level bookmarks" do
      bookmark = Booker::Bookmark.new("|/", "Test Bookmark", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      expect(cleaned).to include("[root]")
      expect(cleaned).not_to include("|/")
    end

    it "should clean folder paths by removing leading |" do
      bookmark = Booker::Bookmark.new("|work/projects/", "Test", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      expect(cleaned).to include("work/projects")
      expect(cleaned).not_to match(/^\|/)  # Should not start with |
    end

    it "should remove trailing slash from folder paths" do
      bookmark = Booker::Bookmark.new("|folder/subfolder/", "Test", "http://test.com", "1")
      cleaned = @bm.clean_name(bookmark)
      expect(cleaned).to include("folder/subfolder |")  # No trailing slash before |
    end
  end

  describe "#clean_link" do
    before do
      allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([fixture_path("bookmarks.json")])
      @bm = Booker::Bookmarks.new
    end

    it "should remove protocol from URLs" do
      bookmark = Booker::Bookmark.new("folder/", "Test", "https://example.com/path", "1")
      cleaned = @bm.clean_link(bookmark)
      expect(cleaned).not_to match(/https?:\/\//)
    end

    it "should remove query parameters" do
      bookmark = Booker::Bookmark.new("folder/", "Test", "http://example.com?foo=bar&baz=qux", "1")
      cleaned = @bm.clean_link(bookmark)
      expect(cleaned).not_to include("?")
    end

    it "should truncate to appropriate width" do
      long_url = "http://example.com/" + ("a" * 500)
      bookmark = Booker::Bookmark.new("folder/", "Test", long_url, "1")
      cleaned = @bm.clean_link(bookmark)
      # Implementation uses [0..Booker::Term.width-Booker::CODEWIDTH] which is inclusive, so length can be +1
      expect(cleaned.length).to be <= (Booker::Term.width - Booker::CODEWIDTH + 1)
    end
  end

  describe "#autocomplete" do
    before do
      allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([fixture_path("bookmarks.json")])
      @bm = Booker::Bookmarks.new("")
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

      # Booker::Folder paths should be cleaned (no leading | in folder part)
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

describe Booker::Bookmark do
  it "should initialize with all attributes" do
    bookmark = Booker::Bookmark.new("folder/", "Test Title", "http://test.com", "123")
    expect(bookmark.folder).to eq("folder/")
    expect(bookmark.title).to eq("test title")  # lowercase
    expect(bookmark.url).to eq("http://test.com")
    expect(bookmark.id).to eq("123")
  end

  it "should clean special characters from title" do
    bookmark = Booker::Bookmark.new("folder/", "Test: 'Title' + More", "http://test.com", "123")
    expect(bookmark.title).not_to include(":")
    expect(bookmark.title).not_to include("'")
    expect(bookmark.title).not_to include("+")
  end

  it "should convert title to lowercase" do
    bookmark = Booker::Bookmark.new("folder/", "UPPERCASE TITLE", "http://test.com", "123")
    expect(bookmark.title).to eq("uppercase title")
  end
end

describe Booker::Folder do
  it "should initialize with title and json" do
    json_data = [{"name" => "Test", "type" => "url"}]
    folder = Booker::Folder.new(json_data, "test/")
    expect(folder.title).to eq("test/")
    expect(folder.json).to eq(json_data)
  end

  it "should clean special characters from title" do
    json_data = []
    folder = Booker::Folder.new(json_data, "test:'folder'")
    expect(folder.title).not_to include(":")
    expect(folder.title).not_to include("'")
  end

  it "should convert title to lowercase" do
    json_data = []
    folder = Booker::Folder.new(json_data, "UPPERCASE")
    expect(folder.title).to eq("uppercase")
  end

  it "should be enumerable" do
    json_data = [{"name" => "Test1"}, {"name" => "Test2"}]
    folder = Booker::Folder.new(json_data, "test/")
    expect(folder).to respond_to(:each)
    expect(folder.to_a.length).to eq(2)
  end
end

describe "Multi-source bookmarks" do
  describe "with multiple sources" do
    before do
      # Mock multiple bookmark sources
      # Two distinct sources so dedup doesn't collapse the second one
      @sources = [fixture_path("bookmarks.json"), fixture_path("safari_bookmarks.plist")]
      allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return(@sources)
    end

    it "should parse from all sources" do
      bm = Booker::Bookmarks.new("")
      results = bm.allurls
      expect(results).not_to be_empty
    end

    it "should prefix IDs with source index" do
      bm = Booker::Bookmarks.new("")
      results = bm.allurls

      # Should have IDs like 0_xxx and 1_xxx
      source_0_ids = results.select { |b| b.id.start_with?("0_") }
      source_1_ids = results.select { |b| b.id.start_with?("1_") }

      expect(source_0_ids).not_to be_empty
      expect(source_1_ids).not_to be_empty
    end

    it "should handle source with nonexistent file" do
      allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([
        fixture_path("bookmarks.json"),
        "/nonexistent/file.json"
      ])

      expect { Booker::Bookmarks.new("") }.not_to raise_error
    end
  end

  describe "with single source" do
    before do
      allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([fixture_path("bookmarks.json")])
    end

    it "should parse from single source" do
      bm = Booker::Bookmarks.new("")
      results = bm.allurls
      expect(results).not_to be_empty
    end

    it "should prefix IDs with 0_" do
      bm = Booker::Bookmarks.new("")
      results = bm.allurls
      expect(results.first.id).to start_with("0_")
    end
  end

  describe "with empty sources" do
    before do
      allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([])
    end

    it "should handle empty source list" do
      expect { Booker::Bookmarks.new("") }.not_to raise_error
    end

    it "should return empty results" do
      bm = Booker::Bookmarks.new("")
      results = bm.allurls
      expect(results).to be_empty
    end
  end
end

describe "#autocomplete_raw" do
  before do
    allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([fixture_path("bookmarks.json")])
    @bm = Booker::Bookmarks.new
  end

  it "prints one tab separated id, title and url per bookmark" do
    output = capture_stdout { @bm.autocomplete_raw }
    expect(output.lines).not_to be_empty

    output.lines.each do |line|
      expect(line.chomp.split("\t").length).to eq(3)
    end
  end

  it "never truncates the url, unlike #autocomplete" do
    longest = @bm.allurls.max_by { |u| u.url.length }
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
