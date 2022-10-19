# rspec testing of booker
require "spec_helper"

# dont actually open links while testing, just ignore
module Browser
  def browse() "echo >/dev/null 2>&1 " end
end


describe Booker do
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
    expect { run('(hi)') }.to output("searching (hi)...\n").to_stdout
    expect { run('    testing spaces  ') }.to output("searching testing spaces...\n").to_stdout
  end

  %w{--install -i --bookmark -b --search -s}.each do |opt|
    it "should have at least 1 cli arg for #{opt}" do
      runblock(opt).should exit_with_code 1
    end
  end

  %w{--version -v --help -h --complete -c}.each do |opt|
    it "should accept valid option #{opt} without args" do
      runblock(opt).should exit_with_code 0
    end
  end

  it "should print the valid version out" do
    %w{--version -v}.each do |opt|
      expect { run(opt) }.to output(Booker.version).to_stdout
    end
  end

  it "should search when given string arguments" do
    ["testing 123", "hi", "mic check mic-check"].each do |str|
      expect { run(str) }.to output("searching #{str}...\n").to_stdout
    end
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
end
