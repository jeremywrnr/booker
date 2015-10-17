# parse web's command line args


VERSION = "0.2"


require 'yaml'
require 'json'
require_relative 'bookmarks'
require_relative 'config'
require_relative 'consts'


# get web opening command
class Booker
  include Browser
  def initialize(args)
    parse args
  end

  def pexit(msg, sig)
    puts msg
    exit sig
  end

  def parse(args)
    if args.none? # no args given, show help
      pexit HELP_BANNER, 1
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
    errormsg = "Error: ".red + "unrecognized option #{nextarg}"
    pexit errormsg, 1 if ! (valid_opts.include? nextarg)

    # doing forced bookmarking
    if args[0] == "--bookmark" or args[0] == "-b"
      bm = Bookmarks.new('')
      id = args[1]
      if id
        url = bm.bookmark_url(id)
        puts 'opening ' + url + '...'
        exec browse << wrap(url)
        exit 0
      else
        pexit '  Error: '.red +
          'web --bookmark expects bookmark id', 1
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

    # doing installation
    if args[0] == "--install" or args[0] == "-i"
      args.shift # remove flag
      if args.length > 0
        install(args)
      else
        pexit '  Error: '.red +
          "web --install expects arguments: [completion, bookmarks, config]", 1
      end
    end

    # doing forced searching
    if args[0] == "--search" or args[0] == "-s"
      args.shift # remove flag
      allargs = args.join(' ')
      if allargs == ""
        pexit "--search requires an argument", 1
      else
        puts 'searching ' + allargs + '...'
        search = BConfig.new.searcher
        exec browse << search << allargs
        exit 0
      end
    end

    # print version information
    if args[0] == "--version" or args[0] == "-v"
      pexit VERSION, 0
    end
  end

  def install(args)
    target = args.shift
    exit 0 if target.nil?

    yaml_config = ENV['HOME'] + '/.booker.yml'

    if /complet/i.match(target) # completion installation
      begin
        # determine where to install function
        fpath = `zsh -c 'echo $fpath'`.split(' ')[0]
        File.open(fpath + "/_web", 'w') {|f| f.write(COMPLETION) }
        loaded = `zsh -c 'autoload -U _web'`
        puts "Success: ".grn +
          "installed zsh autocompletion in #{fpath}"
      rescue
        pexit "Failure: ".red +
          "could not write ZSH completion _web script to $fpath", 1
      end

    elsif /bookmark/i.match(target) # bookmarks installation
      # locate bookmarks file, show user, write to config?
      puts 'searching for chrome bookmarks...'
      begin
        bms = `find ~ -iname '*bookmarks' | grep -i chrom`.split("\n")
        puts 'select your bookmarks file: '
        bms.each_with_index{|bm, i| puts i.to_s.grn + " - " + bm }
        selected = bms[gets.chomp.to_i]
        puts 'selected: ' + selected
        bmconf = 'bookmarks: ' + selected
        open(yaml_config, 'a') { |f| f.write bmconf }
        puts "Success: ".grn +
          "config file updated with bookmarks"
      rescue
        puts "Failure: ".red +
          "could not add bookmarks to config file ~/.booker"
      end

    elsif /config/i.match(target) # default config file generation
      File.open(yaml_config, 'w') {|f| f.write(DEF_CONFIG) }
      puts "Success: ".grn +
        "config file written to ~/.booker"

    else # unknown argument passed into install
      pexit "Failure: ".red +
        "unknown installation option (#{target})", 1
    end

    install(args) # recurse til done
  end
end
