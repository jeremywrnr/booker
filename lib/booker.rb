# parse web's command line args


VERSION = "0.2"


require 'bookmarks'
require 'config'
require 'consts'


# get web opening command
class Booker
  include Browser
  def initialize(args)
    parse args
  end

  def parse(args)
    if args.none? # no args given, show help
      puts HELP_BANNER # from consts.rb
      exit 1
    end

    # if arg starts with hyphen, parse option
    parse_opt args if /^-.*/.match(args[0])

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
        search = BConfig.new.searcher
        exec browse << search << allargs

      end
    end
  end

  def parse_opt(args)
    valid_opts = %w{--version -v --install -i
    --complete -c --bookmark -b --search -s}

    nextarg = args[0]
    if ! (valid_opts.include? nextarg)
      puts "Error: ".red +
        "unrecognized option #{nextarg}"
      exit 1
    end

    # print version information
    if args[0] == "--version" or args[0] == "-v"
      puts VERSION
      exit 0
    end

    # doing installation
    if args[0] == "--install" or args[0] == "-i"
      args.shift # remove flag
      if args.length > 0
        install(args)
      else
        puts "--install expects arguments: [completion, bookmarks, config]"
        exit 1
      end
    end

    # doing autocompletion
    if args[0] == "--complete" or args[0] == "-c"
      args.shift # remove flag
      allargs = args.join(' ')
      bm = Bookmarks.new(allargs)
      bm.autocomplete
      exit 0
    end

    # doing forced bookmarking
    if args[0] == "--bookmark" or args[0] == "-b"
      bm = Bookmarks.new('')
      url = bm.bookmark_url(args[1])
      puts 'opening ' + url + '...'
      exec browse << wrap(url)
      exit 0
    end

    # doing forced searching
    if args[0] == "--search" or args[0] == "-s"
      args.shift # remove flag
      puts 'searching ' + allargs + '...'
      search = BConfig.new.searcher
      exec browse << search << allargs
      exit 0
    end
  end

  def install(args)
    exit 0 unless args.length
    target = args.shift

    if target.match("completion") # completion installation

      # determine where to install function
      fpath = `zsh -c 'echo $fpath'`.split(' ')[0]
      begin
        File.open(fpath + "/_web", 'w') {|f| f.write(COMPLETION) }
        loaded = `unfunction _web && autoload -U _web`
      rescue
        puts "ZSH completion error: could not write _web script to $fpath"
      end

    elsif target.match("bookmarks") # bookmarks installation
      # locate bookmarks file, show user, write to config?
      puts 'searching for bookmarks...'
      potential = `find ~ -iname '*bookmarks' | grep -i chrom`
      puts potential
    elsif target.match("config") # default config file generation
      yaml_config = ENV['HOME'] + '/.booker.yml'
      File.open(fpath + "/_web", 'w') {|f| f.write(DEF_CONFIG) }
    else # unknown argument passed into install
      puts "ZSH completion error: could not write _web script to $fpath"
      exit 1
    end

    install(args) # recurse til done
  end
end
