# grab bookmarks from json file on computer - this may need to be changed based
# on operating system as well


require_relative "folder"
require "rubygems"
require "json"


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
      puts url.folder + '\:' + url.title
    end
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
    if @searching.match(link['name']) or @searching.match(link['url'])
      if link['type'] == 'url'
        @allurls.push(Bookmark.new base, link['name'], link['title'])
      end
    end
  end

  # discover and parse folders
  def parse_folder(base, link)
    if link['type'] == 'folder'
      title = base.title + '/'+ link['name']
      subdir = Folder.new(title, link['children'])
      parse(subdir)
    end
  end
end

# just hold data
class Bookmark
  def initialize(f, t, u)
    @folder = f
    @title = t
    @url = u
  end

  def folder
    @folder
  end

  def title
    @title
  end

  def url
    @url
  end
end
