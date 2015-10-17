# rspec testing of booker


require "spec_helper"


describe Booker do
  def run(str)
    @booker = Booker.new(str.split)
  end

  it "should exit cleanly when no arguments are given" do
    expect { run("") }.to raise_error SystemExit
  end

  it "should refute unrecognized flags" do
    expect { run("-goo?-gaah??''") }.to raise_error SystemExit
    expect { run("-world -goo?") }.to raise_error SystemExit
    expect { run("--hello") }.to raise_error SystemExit
  end

  valid_opts = %w{--version -v --install -i --help -h
    --complete -c --bookmark -b --search -s}
  valid_opts.each do |opt|
    it "should accept valid option flags (#{opt})" do
      expect { run(opt) }.to raise_error SystemExit
    end
  end
end


describe Bookmarks do
  before do
    @rawjson = JSON.parse(open('./spec/bookmarks.json').read)
    @bookmarks = @rawjson['roots']['bookmark_bar']['children']
  end

  it "parses json files correctly" do
    expect(@rawjson).to_not be_nil
  end

  it "parses bookmarks correctly" do
    expect(@bookmarks).to_not be_nil
  end
end
