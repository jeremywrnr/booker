# grab/parse bookmarks from json file on computer

# get int number of columns in half of screen
TERMWIDTH = (TermInfo.screen_size[1]/2).floor

# compl. color codes space
CODEWIDTH = 16


# add some colors, windowing methods
class String
  def window(width)
    if self.length >= width
      self[0..width-1]
    else
      self.ljust(width)
    end
  end

  # thx danhassin/dingbat
  def colorize(color, mod)
    "\033[#{mod};#{color};49m#{self}\033[0;0m"
  end

  def reset() colorize(0,0) end
  def blu() colorize(34,0) end
  def yel() colorize(33,0) end
  def grn() colorize(32,0) end
  def red() colorize(31,0) end
end


# try to read bookmarks
class Bookmarks
  def initialize(search_term = '')
    @conf = BConfig.new
    begin
      local_bookmarks = JSON.parse(open(@conf.bookmarks).read)
      @chrome_bookmarks = local_bookmarks['roots']['bookmark_bar']['children']
    rescue
      puts "Warning: ".yel +
        "Chrome JSON Bookmarks not found."
      puts "Suggest: ".grn +
        "booker --install bookmarks"
      @chrome_bookmarks = {}
    end

    # clean search term, set urls
    @searching = /#{search_term}/i
    @allurls = []
    parse
  end

  # output for zsh autocompetion, print out id, title and cleaned url
  def autocomplete
    @allurls.each do |url|
      name = clean_name(url)
      link = clean_link(url)
      puts url.id + ":" + name + ":" + link
    end
  end

  # clean title for completion, delete anything not allowed in linktitle
  def clean_name(url)
    name = url.folder + ' |' + url.title.gsub(/[^a-z0-9\-\/_ ]/i, '')
    name.gsub!(/\-+/, '-')
    name.gsub!(/[ ]+/,' ')
    name = name.window(TERMWIDTH)
  end

  # clean link for completion, remove strange things from any linkurls
  def clean_link(url)
    link = url.url.gsub(/[,'"&?].*/, '')
    link.gsub!(/.*:\/+/,'')
    link.gsub!(/ /,'')
    link = link[0..TERMWIDTH-CODEWIDTH] # need space for term. color codes
  end

  # get link (from id number)
  def bookmark_url(id)
    @allurls.each do |url|
      return url.url if id == url.id
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
  attr_reader :json, :title
  def initialize(title='|', json)
    @title = title.gsub(/[:,'"]/, '-').downcase
    @json = json
  end

  # needed for Enumerable
  def each() @json.each end
end


# clean bookmark title, set attrs
class Bookmark
  attr_reader :title, :folder, :url, :id
  def initialize(f, t, u, id)
    @title = t.gsub(/[:'"+]/, ' ').downcase
    @folder = f
    @url = u
    @id = id
  end
end
