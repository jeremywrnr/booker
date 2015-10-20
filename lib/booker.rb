# parse web's command line args


VERSION = "0.3"


require 'yaml'
require 'find'
require 'json'
require 'terminfo'
require_relative 'bookmarks'
require_relative 'config'
require_relative 'consts'


# get web opening command
class Booker
  include Browser
  def initialize(args)
    parse args
  end

  def helper
    pexit HELP_BANNER, 1
  end

  def pexit(msg, sig)
    puts msg
    exit sig
  end

  def parse(args)
    # no args given, show help
    helper if args.none?

    # if arg starts with hyphen, parse option
    parse_opt args if /^-.*/.match(args[0])

    # interpret
    while args do
      allargs = "'" + args.join(' ') + "'"
      browsearg = args.shift

      if /[0-9]/.match(browsearg[0]) # bookmark
        bm = Bookmarks.new('')
        url = bm.bookmark_url(browsearg)
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
    valid_opts = %w{--version -v --install -i --help -h
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

    # needs some help
    if args[0] == "--help" or args[0] == "-h"
      helper
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

    if /comp/i.match(target) # completion installation
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
          File.open(fp + "/_web", 'w') {|f| f.write(COMPLETION) }
          system "zsh -c 'autoload -U _web'"
          puts "Success: ".grn +
            "installed zsh autocompletion in #{fp}"
          break # if this works, don't try anymore
        rescue
          puts "Failure: ".red +
            "could not write ZSH completion _web script to $fpath"
        end
      end

    elsif /book/i.match(target) # bookmarks installation
      # locate bookmarks file, show user, write to config?
      puts 'searching for chrome bookmarks... (takes some time)'
      begin
        bms = []
        Find.find(ENV["HOME"]) do |path|
          bms << path if /chrom.*bookmarks/i.match path
        end
        puts 'select your bookmarks file: '
        bms.each_with_index{|bm, i| puts i.to_s.grn + " - " + bm }
        selected = bms[gets.chomp.to_i]
        puts 'Selected: '.yel + selected
        BConfig.new.write('bookmarks', selected)
        puts "Success: ".grn +
          "config file updated with your bookmarks"
      rescue
        pexit "Failure: ".red +
          "could not add bookmarks to config file ~/.booker", 1
      end

    elsif /conf/i.match(target) # default config file generation
      begin
        BConfig.new.write
        puts "Success: ".grn +
          "example config file written to ~/.booker"
      rescue
        pexit "Failure: ".red +
          "could not write example config file to ~/.booker", 1
      end

    else # unknown argument passed into install
      pexit "Failure: ".red +
        "unknown installation option (#{target})", 1
    end

    install(args) # recurse til done
  end
end
