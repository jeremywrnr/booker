# grab bookmarks from json file on computer - this may need to be changed based
# on operating system as well


require_relative "folder"
require "rubygems"
require "json"


# thx danhassin
class String
  def colorize(color, mod)
    "\033[#{mod};#{color};49m#{self}\033[0;0m"
  end

  def window(width)
    if self.length >= width
      self[0..width-1]
    else
      self.ljust(width, '_')
    end
  end

  def reset() colorize(0,0) end
  def white() colorize(37,1) end
  def green() colorize(32,0) end
  def blue() colorize(34,0) end
end


class Bookmarks
  LOCAL_BOOKMARKS = "/Library/Application Support/Google/Chrome/Profile 1/bookmarks"
  RAW_JSON_BOOKMARKS = JSON.parse(open(ENV['HOME'] + LOCAL_BOOKMARKS).read)
  CHROME_BOOKMARKS = RAW_JSON_BOOKMARKS['roots']['bookmark_bar']['children']

  def initialize(search_term)
    @searching = /#{search_term}/i
    @allurls = []
    parse
  end

  # output for zsh
  def autocomplete
    @allurls.each do |url|
      # delete anything not allowed in linktitle
      dirty_t = url.title.gsub(/[^a-z0-9\-\/_]/i, '')
      dirty_t = url.folder + dirty_t
      dirty_t = dirty_t.gsub(/\-+/, '-')
      dirty_t = dirty_t.gsub(/ /,'')
      name = dirty_t.window(50)

      # remove strange things from any linkurls
      dirty_u = url.url.gsub(/[,'"&?].*/, '')
      dirty_u = dirty_u.gsub(/.*:\/+/,'')
      dirty_u = dirty_u.gsub(/ /,'')
      link = dirty_u[0..75]

      # print out title and cleaned url, for autocompetion
      puts url.id + "_" + name + ":" + link
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

# just hold data
class Bookmark
  def initialize(f, t, u, id)
    @title = t.gsub(/[: ,'"+\-]/, '_').downcase
    @folder = f
    @url = u
    @id = id
  end

  def folder
    @folder
  end

  def title
    @title
  end

  def id
    @id
  end

  def url
    @url
  end
end
