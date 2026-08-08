# frozen_string_literal: true

# specs for Booker::CLI: turning argv into an action

RSpec.describe Booker::CLI do
  def catch_exit
    yield
  rescue SystemExit
    nil
  end

  def run(str)
    Booker::CLI.new(str.split)
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
    expect(runblock("")).to exit_with_code 0
  end

  it "should refuse unrecognized flags" do
    expect(runblock("-goo?-gaah??")).to exit_with_code 1
    expect(runblock("-world -goo?")).to exit_with_code 1
    expect(runblock("--hello")).to exit_with_code 1
  end

  it "should handle unescaped chars in the url" do
    expect { run!("(hi)") }.to output(/searching.*\(hi\)/).to_stdout
    expect { run!("    testing spaces  ") }.to output(/searching.*testing\s+spaces/).to_stdout
  end

  %w[--bookmark -b --search -s].each do |opt|
    it "should have at least 1 cli arg for #{opt}" do
      expect(runblock(opt)).to exit_with_code 1
    end
  end

  %w[--version -v --help -h --complete -c].each do |opt|
    it "should accept valid option #{opt} without args" do
      expect(runblock(opt)).to exit_with_code 0
    end
  end

  it "should print the valid version out" do
    %w[--version -v].each do |opt|
      expect { run!(opt) }.to output("#{Booker::VERSION}\n").to_stdout
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
    allow_any_instance_of(Booker::Bookmarks).to receive(:bookmark_url).with("1").and_return("http://example1.com")
    allow_any_instance_of(Booker::Bookmarks).to receive(:bookmark_url).with("2").and_return("http://example2.com")

    expect { run!("1 2") }.to output(/opening bookmark.*example1.*opening bookmark.*example2/m).to_stdout
  end

  it "should separate bookmark IDs from search terms" do
    allow_any_instance_of(Booker::Bookmarks).to receive(:bookmark_url).with("123").and_return("http://example.com")

    # Should open bookmark 123 and search for "github"
    expect { run!("123 github") }.to output(/opening bookmark.*example.*searching.*github/m).to_stdout
  end

  it "should handle URLs with special shell characters" do
    # Test URL with parentheses, ampersands, and other shell metacharacters
    special_url = "https://example.com/path?query=(test)&foo=bar#section"
    allow_any_instance_of(Booker::Bookmarks).to receive(:bookmark_url).with("999").and_return(special_url)

    # Should open without shell errors
    expect { run!("999") }.to output(/opening bookmark.*example\.com/m).to_stdout
    expect { run!("999") }.not_to output(/Syntax error|unexpected/m).to_stdout
  end

  it "should handle URLs with parentheses like Gmail filters" do
    # Real-world example: Gmail with filter syntax
    gmail_url = "https://mail.google.com/mail/u/0/#section_query/(in%3Ainbox+OR+label%3A%5Eiim)+is%3Aunread"
    allow_any_instance_of(Booker::Bookmarks).to receive(:bookmark_url).with("971").and_return(gmail_url)

    # Should open without shell errors
    expect { run!("971") }.to output(/opening bookmark.*mail\.google\.com/m).to_stdout
    expect { run!("971") }.not_to output(/Syntax error|unexpected/m).to_stdout
  end
end

RSpec.describe "Integration tests" do
  before do
    allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([fixture_path("bookmarks.json")])
  end

  it "should handle full search workflow" do
    bm = Booker::Bookmarks.new("chrome")
    results = bm.allurls
    expect(results).not_to be_empty

    first_id = results.first.id
    url = bm.bookmark_url(first_id)
    expect(url).not_to be_nil
  end

  it "should handle autocomplete output" do
    bm = Booker::Bookmarks.new("chrome")
    expect { bm.autocomplete }.to output(/\d+_\d+:.*:.*/).to_stdout
  end

  it "should handle case-insensitive search" do
    bm_lower = Booker::Bookmarks.new("chrome")
    bm_upper = Booker::Bookmarks.new("CHROME")
    bm_mixed = Booker::Bookmarks.new("ChRoMe")

    expect(bm_lower.allurls.length).to eq(bm_upper.allurls.length)
    expect(bm_lower.allurls.length).to eq(bm_mixed.allurls.length)
  end

  it "should search across title, URL, and folder" do
    # Create bookmark with search term in different fields
    bm_title = Booker::Bookmarks.new("chrome")  # matches title
    bm_url = Booker::Bookmarks.new("http")       # matches URL
    bm_folder = Booker::Bookmarks.new("r")       # matches folder names

    expect(bm_title.allurls).not_to be_empty
    expect(bm_url.allurls).not_to be_empty
    expect(bm_folder.allurls).not_to be_empty
  end
end

RSpec.describe "argument dispatch" do
  # CLI#initialize parses argv immediately, so allocate one to poke at the
  # dispatch methods on their own
  let(:booker) { Booker::CLI.allocate }

  before do
    allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([fixture_path("bookmarks.json")])
  end

  it "opens an argument that looks like a website" do
    expect(capture_stdout { Booker::CLI.new(["example.com"]) }).to include("opening website")
  end

  it "explains how to install when there are no bookmarks at all" do
    allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([])

    output = capture_stdout do
      expect { Booker::CLI.new([]) }.to raise_error(SystemExit)
    end

    expect(output).to include("No bookmarks found")
  end

  it "routes --install with no argument to the default installers" do
    expect(booker.installer).to receive(:install).with(%w[completion config bookmarks])
    booker.dispatch_option(["-i"])
  end

  it "routes --bookmark to opening that bookmark" do
    expect(booker).to receive(:open_bookmark).with(["1"])
    booker.dispatch_option(["-b", "1"])
  end

  it "routes --search to a search" do
    expect(capture_stdout { booker.dispatch_option(["-s", "hello"]) }).to include("searching")
  end

  it "routes --complete-raw to the tab separated feed" do
    expect(capture_stdout { booker.dispatch_option(["--complete-raw"]) }).to include("\t")
  end
end

RSpec.describe "bookmark ids handed over by tab completion" do
  # completion inserts an id from the raw feed, so every id that feed emits has
  # to come back as a bookmark rather than as a search term
  before do
    allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([
      fixture_path("bookmarks.json"),
      fixture_path("safari_bookmarks.plist")
    ])
  end

  def ids
    Booker::Bookmarks.new("").allurls.map(&:id)
  end

  it "recognizes every id the raw feed emits, whatever browser it came from" do
    expect(ids).not_to be_empty
    expect(ids.grep_v(Booker::CLI::BOOKMARK_ID)).to be_empty
  end

  it "opens a safari uuid rather than searching for it" do
    uuid = ids.find { |id| /[a-z]/i.match?(id) }
    expect(uuid).not_to be_nil

    output = capture_stdout { Booker::CLI.new([uuid]) }
    expect(output).to include("opening bookmark")
    expect(output).not_to include("searching")
  end

  it "still sends a plain word to the search engine" do
    expect(capture_stdout { Booker::CLI.new(["github"]) }).to include("searching")
  end
end

RSpec.describe "the bookmark table" do
  # reads from the fixture rather than from whatever the developer has in
  # chrome, so the table rendering is exercised everywhere
  before do
    allow_any_instance_of(Booker::Config).to receive(:bookmarks)
      .and_return([fixture_path("bookmarks.json")])
  end

  it "prints a row per bookmark and then the usage examples" do
    output = capture_stdout do
      expect { Booker::CLI.new([]) }.to raise_error(SystemExit)
    end

    expect(output).to include("Bookmarks:")
    expect(output).to match(/Found \d+ bookmarks/)
    expect(output).to include("Examples:")
    expect(output).to include("booker --help")
  end

  it "puts the id, folder, title and url on each row" do
    output = capture_stdout do
      expect { Booker::CLI.new([]) }.to raise_error(SystemExit)
    end

    first = Booker::Bookmarks.new("").allurls.first
    row = output.lines.find { |l| l.include?(first.id) }

    expect(row).not_to be_nil
    expect(row).to include(first.url[0, 20])
  end
end

RSpec.describe "the interactive picker" do
  # the picker replaces the two entry points that used to dead end: bare
  # `booker`, which only ever printed a table, and a search term that matches
  # bookmarks, which only ever reached the search engine
  before do
    allow_any_instance_of(Booker::Config).to receive(:bookmarks)
      .and_return([fixture_path("bookmarks.json")])
    Booker::Picker.enabled = true
  end

  # every path here ends in exit, and SystemExit is not a StandardError - one
  # escaping an example would abort rspec itself
  def catch_exit
    yield
  rescue SystemExit
    nil
  end

  def first_id = Booker::Bookmarks.new("").allurls.first.id

  def picks(*ids)
    allow_any_instance_of(Booker::Picker).to receive(:select).and_return(ids)
  end

  it "opens what was picked instead of printing the table" do
    picks(first_id)
    output = capture_stdout { catch_exit { Booker::CLI.new([]) } }

    expect(output).to include("opening bookmark")
    expect(output).not_to include("Found ")
  end

  it "offers a matching search term as a choice rather than searching for it" do
    picks(first_id)
    output = capture_stdout { catch_exit { Booker::CLI.new(["github"]) } }

    expect(output).to include("opening bookmark")
    expect(output).not_to include("searching")
  end

  it "hands the picker every match, not just the first" do
    expect_any_instance_of(Booker::Picker).to receive(:select) do |_, rows|
      expect(rows.length).to eq(Booker::Bookmarks.new("github").allurls.length)
      expect(rows).to all(include("\t"))
      []
    end

    catch_exit { Booker::CLI.new(["github"]) }
  end

  it "opens every bookmark when several are picked" do
    ids = Booker::Bookmarks.new("github").allurls.first(2).map(&:id)
    picks(*ids)
    output = capture_stdout { catch_exit { Booker::CLI.new(["github"]) } }

    expect(output.scan("opening bookmark").length).to eq(2)
  end

  it "does nothing at all when the picker is cancelled" do
    picks
    output = capture_stdout do
      expect { Booker::CLI.new(["github"]) }.to exit_with_code(0)
    end

    expect(output).not_to include("opening bookmark")
    expect(output).not_to include("searching")
  end

  it "still searches for a term that matches no bookmark" do
    expect_any_instance_of(Booker::Picker).not_to receive(:select)
    expect(capture_stdout { catch_exit { Booker::CLI.new(["zzzznotabookmark"]) } })
      .to include("searching")
  end

  it "still opens a bare url without offering a choice" do
    expect_any_instance_of(Booker::Picker).not_to receive(:select)
    expect(capture_stdout { Booker::CLI.new(["example.com"]) })
      .to include("opening website")
  end

  it "falls back to the old behavior when no finder is installed" do
    Booker::Picker.enabled = false
    expect(capture_stdout { catch_exit { Booker::CLI.new(["github"]) } })
      .to include("searching")
  end

  it "prints the table anyway for --list" do
    output = capture_stdout do
      expect { Booker::CLI.allocate.dispatch_option(["-l"]) }.to exit_with_code(0)
    end

    expect(output).to include("Bookmarks:")
    expect(output).to match(/Found \d+ bookmarks/)
  end

  it "explains how to install when there are no bookmarks to pick from" do
    allow_any_instance_of(Booker::Config).to receive(:bookmarks).and_return([])
    expect_any_instance_of(Booker::Picker).not_to receive(:select)

    output = capture_stdout { catch_exit { Booker::CLI.new([]) } }
    expect(output).to include("No bookmarks found")
  end
end

RSpec.describe "urls handed over by tab completion" do
  # completion inserts the bookmark url rather than its id, and zsh's automenu
  # lets you pick several before hitting return, so a line of them has to open
  # every one
  before do
    allow_any_instance_of(Booker::Config).to receive(:bookmarks)
      .and_return([fixture_path("bookmarks.json")])
  end

  def urls = Booker::Bookmarks.new("").allurls.map(&:url)

  it "opens a single completed url" do
    expect(capture_stdout { Booker::CLI.new([urls.first]) })
      .to include("opening website")
  end

  it "opens every url on the line, not just the first" do
    output = capture_stdout { Booker::CLI.new(urls.first(3)) }
    expect(output.scan("opening website").length).to eq(3)
  end

  it "recognizes every url the raw feed emits as a url" do
    matcher = Booker::CLI.allocate.domain
    expect(urls).not_to be_empty
    expect(urls.reject { |u| matcher.match?(u) }).to be_empty
  end

  it "still treats a phrase containing a domain as a search" do
    expect(capture_stdout { Booker::CLI.new(%w[read example.com later]) })
      .to include("searching")
  end
end
