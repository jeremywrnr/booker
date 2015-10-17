# parse command line args


require_relative 'config'
require_relative 'bookmarks'


# get web opening command
class Booker
  def initialize(args)
    parse args
  end

  def parse(args)
    if args.none? # no args given, show help
      puts HELP_BANNER # from consts.rb
      exit 1
    end

    # doing installation
    if args[0] == "--install"
      args.shift # remove flag
      install(args)
      exit 0
    end

    # doing autocompletion
    if args[0] == "--complete"
      args.shift # remove flag
      allargs = args.join(' ')
      bm = Bookmarks.new(allargs)
      bm.autocomplete
      exit 0
    end

    # doing forced bookmarking
    if args[0] == "--bookmark" or args[0] == "-b"
      bm = Bookmarks.new('')
      bookmark = bm.bookmark_id(args[1])
      url = bm.bookmark_url(bookmark)
      puts 'opening ' + url + '...'
      exec browse << wrap(url)
      exit 0
    end

    # doing forced searching
    if args[0] == "--search" or args[0] == "-s"
      args.shift # remove flag
      puts 'searching ' + allargs + '...'
      exec browse << search << allargs
      exit 0
    end

    # interpret
    while args do
      allargs = "'" + args.join(' ') + "'"
      browsearg = args.shift

      if /[0-9]/.match(browsearg[0]) # bookmark
        bm = Bookmarks.new('')
        bookmark = bm.bookmark_id(browsearg)
        url = bm.bookmark_url(bookmark)
        puts 'opening ' + url + '...'
        exec browse << wrap(url)

      elsif domain.match(browsearg) # website
        puts 'opening ' + browsearg + '...'
        exec browse << wrap(prep(browsearg))

      else # just search for these arguments
        puts 'searching ' + allargs + '...'
        exec browse << search << allargs

      end
    end
  end

  def install(args)
    # TODO bookmarks installation

    # determine where to install function
    fpath = `zsh -c 'echo $fpath'`.split(' ')[0]
    if fpath
      File.open(fpath + "/_web", 'w') {|f| f.write(COMPLETION) }
    else
      puts "web zsh completion error, could not write _web script to $fpath"
    end
  end
end

