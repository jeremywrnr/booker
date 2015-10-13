# grab/parse bookmarks from json file on computer


require "json"
require_relative "config"


class String
  def window(width)
    if self.length >= width
      self[0..width-1]
    else
      self.ljust(width)
    end
  end
end


class Bookmarks
  extend BookerConfig
  # try to read bookmarks
  begin
    LOCAL_BOOKMARKS = JSON.parse(open(BookerConfig.bookmarks).read)
    CHROME_BOOKMARKS = LOCAL_BOOKMARKS['roots']['bookmark_bar']['children']
  rescue
    CHROME_BOOKMARKS = {}
  end

  def initialize(search_term)
    @searching = /#{search_term}/i
    @allurls = []
    parse
  end

  # output for zsh
  def autocomplete
    width = 80
    @allurls.each do |url|
      # delete anything not allowed in linktitle
      name = url.folder + url.title.gsub(/[^a-z0-9\-\/_]/i, '')
      name.gsub!(/\-+/, '-').gsub!(/ /,'')
      name = name.window(width)

      # remove strange things from any linkurls
      link = url.url.gsub(/[,'"&?].*/, '')
      link.gsub!(/.*:\/+/,'').gsub!(/ /,'')
      link = dirty_u[0..width]

      # print out title and cleaned url, for autocompetion
      puts url.id + ":" + name + ":" + link
    end
  end

  # parse a bookmark's id from tab completed form
  def bookmark_id(url)
    url[0..5].gsub(/[^0-9]/, '')
  end

  # get link (from id number)
  def bookmark_url(id)
    bm_url = ''
    @allurls.each do |url|
      bm_url = url.url if id == url.id
    end
    bm_url
  end

  # recursively parse gc bookmarks
  def parse(root=nil)
    # root - parent folder in ruby
    root = Folder.new CHROME_BOOKMARKS if root.nil?

    # all current urls, to hash
    root.json.each {|x| parse_link root.title, x }

    # all next-level folders, to array
    root.json.each {|x| parse_folder root, x }
  end

  # add link to results
  def parse_link(base, link)
    checking = [base, link['name'], link['url'], link['id']]
    if checking.any? {|x| @searching.match x }
      if link['type'] == 'url'
        @allurls.push(Bookmark.new base, link['name'], link['url'], link['id'])
      end
    end
  end

  # discover and parse folders
  def parse_folder(base, link)
    if link['type'] == 'folder'
      title = base.title + link['name'] + '/'
      subdir = Folder.new(title, link['children'])
      parse(subdir)
    end
  end
end


# basic folder class, for parsing bookmarks
class Folder
  include Enumerable
  def initialize(title='/', json)
    @title = title.gsub(/[: ,'"]/, '-').downcase
    @json = json
  end

  def title() @title end
  def json() @json end
  def each() @json.each end
end


# clean bookmark title, set attrs
class Bookmark
  def initialize(f, t, u, id)
    @title = t.gsub(/[: ,'"+\-]/, '_').downcase
    @folder = f
    @url = u
    @id = id
  end

  def folder() @folder end
  def title() @title end
  def url() @url end
  def id() @id end
end
