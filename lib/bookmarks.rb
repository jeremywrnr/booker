# grab/parse bookmarks from json file on computer


TERMWIDTH = 80


class String
  def window(width)
    if self.length >= width
      self[0..width-1]
    else
      self.ljust(width)
    end
  end

  def colorize(color, mod)
    "\033[#{mod};#{color};49m#{self}\033[0;0m"
  end

  def reset() colorize(0,0) end
  def blu() colorize(34,0) end
  def yel() colorize(33,0) end
  def grn() colorize(32,0) end
  def red() colorize(31,0) end
end


class Bookmarks
  # try to read bookmarks
  def initialize(search_term)
    @conf = BConfig.new
    begin
      local_bookmarks = JSON.parse(open(@conf.bookmarks).read)
      @chrome_bookmarks = local_bookmarks['roots']['bookmark_bar']['children']
    rescue
      puts "Warning: ".yel +
        "Chrome JSON Bookmarks not found."
      puts "Suggest: ".grn +
        "web --install bookmarks"
      @chrome_bookmarks = {}
    end

    # clean search term, set urls
    @searching = /#{search_term}/i
    @allurls = []
    parse
  end


  # output for zsh
  def autocomplete
    @allurls.each do |url|
      # delete anything not allowed in linktitle
      name = url.folder + url.title.gsub(/[^a-z0-9\-\/_]/i, '')
      name.gsub!(/\-+/, '-')
      name.gsub!(/ /,'')
      name = name.window(TERMWIDTH)

      # remove strange things from any linkurls
      link = url.url.gsub(/[,'"&?].*/, '')
      link.gsub!(/.*:\/+/,'')
      link.gsub!(/ /,'')
      link = link[0..TERMWIDTH]

      # print out title and cleaned url, for autocompetion
      puts url.id + ":" + name + ":" + link
    end
  end

  # get link (from id number)
  def bookmark_url(id)
    @allurls.each do |url|
      if id == url.id
        return url.url
      end
    end
  end

  # recursively parse gc bookmarks
  def parse(root=nil)
    # root - parent folder in ruby
    root = Folder.new @chrome_bookmarks if root.nil?

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
end # close bookmarks class


# for recursively parsing bookmarks
class Folder
  include Enumerable
  def initialize(title='/', json)
    @title = title.gsub(/[: ,'"]/, '-').downcase
    @json = json
  end

  def json() @json end
  def title() @title end
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
