# rspec testing of booker


require "spec_helper"


describe Booker do
  def run_booker()
  end

  it "can read json file of bookmarks" do
  end
end


describe Bookmarks do
  before do
    @bookmarks = JSON.parse(open('./spec/bookmarks.json').read)['roots']['bookmark_bar']['children']
  end

  it "parses json file correctly" do
  end
end
