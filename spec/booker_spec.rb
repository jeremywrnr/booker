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
    expect { runblock('') }.to exit_with_code 0
  end

  #it "should refuse unrecognized flags" do
  #expect { runblock("-goo?-gaah??") }.to exit_with_code 1
  #expect { runblock("-world -goo?") }.to exit_with_code 1
  #expect { runblock("--hello") }.to exit_with_code 1
  #end

  #valid_opts = %w{--version -v --install -i --help -h
  #--complete -c --bookmark -b --search -s}
  #valid_opts.each do |opt|
  #it "should accept valid option flags (#{opt})" do
  #expect { runblock(opt) }.to exit_with_code 0
  #end
  #end

  it "should search for string arguments" do
    ['testing 123', 'mic check mic-check'].each do |str|
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
