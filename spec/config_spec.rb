# frozen_string_literal: true

# specs for Booker::Config, Booker::OS and Booker::Browser

RSpec.describe Booker::Config do
  it "bookmarks method should return an array" do
    config = Booker::Config.new
    result = config.bookmarks
    expect(result).to be_a(Array)
  end

  it "should handle single-path string configs (backward compatibility)" do
    config = Booker::Config.new
    config.instance_variable_set(:@config, {bookmarks: "/path/to/Bookmarks"})
    result = config.bookmarks
    expect(result).to eq(["/path/to/Bookmarks"])
  end

  it "should handle multi-source array configs" do
    config = Booker::Config.new
    paths = ["/path/to/Bookmarks", "/path/to/places.sqlite"]
    config.instance_variable_set(:@config, {bookmarks: paths})
    result = config.bookmarks
    expect(result).to eq(paths)
  end

  it "should discover multiple bookmark sources" do
    config = Booker::Config.new
    sources = config.discover_all_bookmark_sources
    expect(sources).to be_a(Array)
  end

  it "should validate config keys" do
    config = Booker::Config.new
    # initialize rebuilds @config from the yaml file, so setting @config
    # directly gets overwritten - stub the read instead
    allow(config).to receive(:read).and_return({bookmarks: "/path", invalid_key: "value"})

    expect { config.send(:initialize) }.to raise_error(SystemExit)
  end

  it "should return searcher URL" do
    config = Booker::Config.new
    searcher = config.searcher
    expect(searcher).to be_a(String)
    expect(searcher).to match(/^https?:/)
  end

  it "should handle missing config file gracefully" do
    allow(File).to receive(:exist?).and_return(false)
    expect { Booker::Config.new }.not_to raise_error
  end
end

RSpec.describe "Booker::Browser module" do
  include Booker::Browser

  describe "#browse" do
    it "should return xdg-open on Linux" do
      allow(Booker::OS).to receive(:linux?).and_return(true)
      allow(Booker::OS).to receive(:mac?).and_return(false)
      allow(Booker::OS).to receive(:windows?).and_return(false)
      expect(real_browse).to eq("xdg-open ")
    end

    it "should return open on macOS" do
      allow(Booker::OS).to receive(:linux?).and_return(false)
      allow(Booker::OS).to receive(:mac?).and_return(true)
      allow(Booker::OS).to receive(:windows?).and_return(false)
      expect(real_browse).to eq("open ")
    end

    it "should return the chrome executable on windows" do
      allow(Booker::OS).to receive(:windows?).and_return(true)
      expect(real_browse).to include("chrome.exe")
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
end

RSpec.describe "Booker::Sources.profiles" do
  around do |example|
    Dir.mktmpdir do |tmp|
      @base = tmp
      example.run
    end
  end

  def write_ini(body)
    path = File.join(@base, "profiles.ini")
    File.write(path, body)
    path
  end

  def add_profile(name)
    FileUtils.mkdir_p(File.join(@base, name))
    FileUtils.touch(File.join(@base, name, "places.sqlite"))
    File.join(@base, name, "places.sqlite")
  end

  it "returns the database of every profile that has one" do
    first = add_profile("one.default")
    second = add_profile("two.dev")
    ini = write_ini(<<~INI)
      [Profile0]
      Name=default
      Path=one.default

      [Profile1]
      Name=dev
      Path=two.dev
    INI

    expect(Booker::Sources.profiles(ini, @base)).to contain_exactly(first, second)
  end

  it "skips profiles whose database has not been created yet" do
    real = add_profile("real.default")
    ini = write_ini(<<~INI)
      [Profile0]
      Path=real.default

      [Profile1]
      Path=ghost.default
    INI

    expect(Booker::Sources.profiles(ini, @base)).to eq([real])
  end

  it "returns nothing when no profile declares a path" do
    ini = write_ini("[General]\nStartWithLastProfile=1\n")
    expect(Booker::Sources.profiles(ini, @base)).to be_empty
  end

  # firefox writes the profile an install last used a second time, under
  # [Install...], so counting Path= lines would offer the same database twice
  it "lists a profile once even when the install section names it again" do
    real = add_profile("one.default")
    ini = write_ini(<<~INI)
      [Profile0]
      Path=one.default

      [Install4F96D1932A9F858E]
      Default=one.default
      Path=one.default
    INI

    expect(Booker::Sources.profiles(ini, @base)).to eq([real])
  end
end

RSpec.describe Booker::OS do
  it "identifies exactly one platform for the host it runs on" do
    expect([Booker::OS.windows?, Booker::OS.mac?, Booker::OS.linux?].count(true)).to eq(1)
  end
end

RSpec.describe "Booker::Config file handling" do
  # allocate skips initialize, which would read the developer's real ~/.booker.yml
  let(:config) { Booker::Config.allocate }

  it "falls back to defaults when the config file is missing" do
    expect(config.read("/nonexistent/.booker.yml")).to be false
  end

  it "falls back to defaults when the config file is not valid yaml" do
    Dir.mktmpdir do |tmp|
      bad = File.join(tmp, "bad.yml")
      File.write(bad, "searcher: [unclosed\n")
      expect(config.read(bad)).to be false
    end
  end

  # psych 4 stopped allowing aliases by default, so a config using anchors
  # raises AliasesNotEnabled rather than SyntaxError - it still has to fall back
  it "falls back to defaults when the config file uses yaml anchors" do
    Dir.mktmpdir do |tmp|
      aliased = File.join(tmp, "aliased.yml")
      File.write(aliased, ":searcher: &s https://example.com/?q=\n:browser: *s\n")
      expect(config.read(aliased)).to be false
    end
  end

  it "round trips the symbol keys #write emits" do
    Dir.mktmpdir do |tmp|
      target = File.join(tmp, ".booker.yml")
      File.write(target, {searcher: "https://example.com/?q=", bookmarks: ["/a"]}.to_yaml)
      expect(config.read(target)).to eq(searcher: "https://example.com/?q=", bookmarks: ["/a"])
    end
  end

  it "writes updated keys back out as yaml" do
    Dir.mktmpdir do |tmp|
      target = File.join(tmp, ".booker.yml")
      stub_const("Booker::Config::YAMLCONF", target)

      Booker::Config.new.write(:searcher, "https://example.com/?q=")

      expect(YAML.load_file(target)[:searcher]).to eq("https://example.com/?q=")
    end
  end

  it "discovers chrome bookmarks sitting under a profile directory" do
    Dir.mktmpdir do |tmp|
      stub_const("Booker::Config::HOME", tmp)
      profile = File.join(tmp, ".config/chromium/Default")
      FileUtils.mkdir_p(profile)
      File.write(File.join(profile, "Bookmarks"), "{}")

      sources = Booker::Config.allocate.discover_all_bookmark_sources
      expect(sources).to include(File.join(profile, "Bookmarks"))
    end
  end
end

RSpec.describe "Booker::Config against a home with no browsers" do
  # HOME is read into a constant at load time, so these stub it rather than
  # touching ENV - and they never depend on what the developer has installed
  around do |example|
    Dir.mktmpdir do |tmp|
      @home = tmp
      example.run
    end
  end

  def config
    stub_const("Booker::Config::HOME", @home)
    Booker::Config.allocate
  end

  it "hands back a parsed config when the yaml is valid" do
    target = File.join(@home, ".booker.yml")
    File.write(target, {searcher: "https://example.com/?q="}.to_yaml)

    expect(Booker::Config.allocate.read(target)).to eq({searcher: "https://example.com/?q="})
  end

  it "falls back to the chrome default when no browser is installed" do
    expect(config.detect_default_bookmarks)
      .to include("Library/Application Support/Google/Chrome")
  end

  it "prefers every source it can find over that fallback" do
    profile = File.join(@home, ".config/chromium/Default")
    FileUtils.mkdir_p(profile)
    File.write(File.join(profile, "Bookmarks"), "{}")

    expect(config.detect_default_bookmarks).to eq([File.join(profile, "Bookmarks")])
  end

  # a chrome directory booker cannot read is one source it does not offer, not
  # a backtrace in the middle of an ordinary search
  it "skips a chrome directory that cannot be walked" do
    FileUtils.mkdir_p(File.join(@home, ".config/chromium"))
    allow(Dir).to receive(:glob).and_raise(Errno::EACCES)

    stub_const("Booker::Config::HOME", @home)
    expect(Booker::Sources.discover).to be_empty
  end

  it "discovers the firefox profiles listed in profiles.ini" do
    base = File.join(@home, ".mozilla/firefox")
    FileUtils.mkdir_p(File.join(base, "abc.default"))
    FileUtils.touch(File.join(base, "abc.default", "places.sqlite"))
    File.write(File.join(base, "profiles.ini"), "[Profile0]\nPath=abc.default\n")

    expect(config.discover_all_bookmark_sources)
      .to eq([File.join(base, "abc.default", "places.sqlite")])
  end
end

RSpec.describe "Booker::Config picker key" do
  def config_with(yaml)
    Dir.mktmpdir do |tmp|
      target = File.join(tmp, ".booker.yml")
      File.write(target, yaml)
      stub_const("Booker::Config::YAMLCONF", target)
      yield Booker::Config.new
    end
  end

  it "accepts a picker command rather than exiting on an unknown key" do
    config_with({picker: "sk --height=40%", bookmarks: ["/a"]}.to_yaml) do |config|
      expect(config.picker).to eq("sk --height=40%")
    end
  end

  it "is nil when the config does not name one" do
    config_with({bookmarks: ["/a"]}.to_yaml) do |config|
      expect(config.picker).to be_nil
    end
  end

  # the key is deliberately absent from the generated defaults: a config naming
  # it cannot be read by a booker old enough to predate the key
  it "is not written into a freshly generated config" do
    Dir.mktmpdir do |tmp|
      target = File.join(tmp, ".booker.yml")
      stub_const("Booker::Config::YAMLCONF", target)

      Booker::Config.new.write

      expect(YAML.load_file(target)).not_to have_key(:picker)
    end
  end
end

RSpec.describe "Booker::Browser#prep against completed urls" do
  include Booker::Browser

  # tab completion inserts real bookmark urls, and browsers store plenty that
  # are not http - testing for "http" alone turned those into nonsense
  it "leaves any explicit scheme alone" do
    expect(prep("chrome://bookmarks/")).to eq("chrome://bookmarks/")
    expect(prep("file:///Users/me/notes.html")).to eq("file:///Users/me/notes.html")
    expect(prep("ftp://example.com/pub")).to eq("ftp://example.com/pub")
  end

  it "still invents a scheme for a bare host" do
    expect(prep("example.com/path")).to eq("http://example.com/path")
  end
end
