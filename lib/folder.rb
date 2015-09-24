# basic folder class, for parsing bookmarks

class Folder
  include Enumerable
  def initialize(title='/', json)
    @title = title
    @json = json
  end

  def title
    @title
  end

  def json
    @json
  end

  def each
    @json.each
  end
end
