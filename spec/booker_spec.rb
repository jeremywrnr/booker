# rspec testing of booker


require "spec_helper"


# dont actually open links while testing
module Browser
  def browse() 'echo ' end
end


describe Booker do
  def run(str)
    Booker.new(str.split)
  end

  def runblock(str)
    lambda { run(str) }
  end

  it "should exit cleanly when no arguments are given" do
    runblock('').should exit_with_code 0
  end

  it "should refuse unrecognized flags" do
    runblock("-goo?-gaah??").should exit_with_code 1
    runblock("-world -goo?").should exit_with_code 1
    runblock("--hello").should exit_with_code 1
  end

  %w{--install -i --bookmark -b --search -s}.each do |opt|
    it "needs at least 1 cli argument for option #{opt}" do
      runblock(opt).should exit_with_code 1
    end
  end

  %w{--version -v --help -h --complete -c}.each do |opt|
    it "should accept valid option #{opt} without args" do
      runblock(opt).should exit_with_code 0
    end
  end

  it "should search when given string arguments" do
    ['testing 123', 'hi', 'mic check mic-check'].each do |str|
      expect { run(str) }.to output("searching '#{str}'...\n").to_stdout
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
