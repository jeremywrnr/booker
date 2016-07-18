# parse booker's command line args


VERSION = "0.5"


require 'yaml'
require 'find'
require 'json'
require 'terminfo'
require 'shellwords'
require_relative 'bookmarks'
require_relative 'config'
require_relative 'consts'


# get web opening command
class Booker
  include Browser
  def initialize(args)
    parse args
  end

  def parse(args)
    # no args given, show help
    helper if args.none?

    # if arg starts with hyphen, parse option
    parse_opt args if /^-.*/.match(args.first)

    # interpret command
    browsearg = args.first

    if browsearg.match(/^[0-9]/) # bookmark
      open_bookmark args
    elsif domain.match(browsearg) # website
      puts 'opening website ' + browsearg + '...'
      openweb(wrap(prep(browsearg)))
    else
      allargs = wrap(args.join(' '))
      open_search allargs
    end
  end

  def pexit(msg, sig)
    puts msg
    exit sig
  end

  def helper
    pexit HELP_BANNER, 0
  end

  def version
    pexit VERSION, 0
  end

  def openweb(url)
    system(browse + wrap(url))
  end

  # an array of ints, as bookmark ids
  def open_bookmark(bm)
    id = bm.shift
    url = Bookmarks.new.bookmark_url(id)
    pexit "Failure:".red + " bookmark #{id} not found", 1 if url.nil?
    puts 'opening bookmark ' + url + '...'
    openweb(wrap(url))
    open_bookmark bm unless bm.empty?
  end

  def open_search(term)
    puts 'searching ' + term + '...'
    search = BConfig.new.searcher
    openweb(Shellwords.escape(search + term))
  end

  # parse and execute any command line options
  def parse_opt(args)
    valid_opts = %w{--version -v --install -i --help -h
    --complete -c --bookmark -b --search -s}

    nextarg = args.shift
    errormsg = 'Error: '.red + "unrecognized option #{nextarg}"
    pexit errormsg, 1 if ! (valid_opts.include? nextarg)

    # doing forced bookmarking
    if nextarg == '--bookmark' || nextarg == '-b'
      if args.first.nil?
        pexit 'Error: '.red + 'booker --bookmark expects bookmark id', 1
      else
        open_bookmark args
      end
    end

    # doing autocompletion
    if nextarg == '--complete' || nextarg == '-c'
      allargs = args.join(' ')
      bm = Bookmarks.new(allargs)
      bm.autocomplete
    end

    # doing installation
    if nextarg == '--install' || nextarg == '-i'
      if !args.empty?
        install(args)
      else
        err = 'booker --install expects arguments: [completion, bookmarks, config]'
        pexit 'Error: '.red + err, 1
      end
    end

    # doing forced searching
    if nextarg == '--search' || nextarg == '-s'
      pexit '--search requires an argument', 1 if args.empty?
      allargs = args.join(' ')
      open_search allargs
    end

    # print version information
    version if nextarg == '--version' || nextarg == '-v'

    # needs some help
    helper if nextarg == '--help' || nextarg == '-h'

    exit 0 # dont parse_arg
  end # parse_opt

  def install(args)
    target = args.shift
    exit 0 if target.nil?

    if /comp/i.match(target) # completion installation
      install_completion
    elsif /book/i.match(target) # bookmarks installation
      install_bookmarks
    elsif /conf/i.match(target) # default config file generation
      install_config
    else # unknown argument passed into install
      pexit "Failure: ".red + "unknown installation option (#{target})", 1
    end

    install(args) # recurse til done
  end

  def install_completion
    # check if zsh is even installed for this user
    begin
      fpath = `zsh -c 'echo $fpath'`.split(' ')
    rescue
      pexit "Failure: ".red +
        "zsh is probably not installed, could not find $fpath", 1
    end

    # determine where to install completion function
    fpath.each do |fp|
      begin
        File.open(fp + "/_booker", 'w') {|f| f.write(COMPLETION) }
        system "zsh -c 'autoload -U _booker'"
        puts "Success: ".grn +
          "installed zsh autocompletion in #{fp}"
        break # if this works, don't try anymore
      rescue
        puts "Failure: ".red +
          "could not write ZSH completion _booker script to $fpath (#{fp})"
      end
    end
  end

  def install_bookmarks
    # locate bookmarks file, show user, write to config?
    puts 'searching for chrome bookmarks... (takes some time)'
    begin
      bms = [] # look for bookmarks
      Find.find(ENV["HOME"]) do |path|
        bms << path if /chrom.*bookmarks/i.match path
      end

      if bms.empty? # no bookmarks found
        puts "Failure: ".red + 'bookmarks file could not be found.'
        raise
      else # have user select a file
        puts 'select your bookmarks file: '
        bms.each_with_index{|bm, i| puts i.to_s.grn + " - " + bm }
        selected = bms[gets.chomp.to_i]
        puts 'Selected: '.yel + selected
        BConfig.new.write('bookmarks', selected)
        puts "Success: ".grn +
          "config file updated with your bookmarks"
      end
    rescue # catch all errors
      pexit "Failure: ".red +
        "could not add bookmarks to config file ~/.booker", 1
    end
  end

  def install_config
    begin
      BConfig.new.write
      puts "Success: ".grn +
        "example config file written to ~/.booker"
    rescue
      pexit "Failure: ".red +
        "could not write example config file to ~/.booker", 1
    end
  end
end
