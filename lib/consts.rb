# file for large constant strings


HELP_BANNER = <<-EOS
Open browser:
    $ web [option] [arguments]

Main options:
    --bookmark, -b: explicity open bookmark
     --install, -i: install [bookmarks, completion, config]
      --search, -s: explicity search arguments

Others:
    --complete, -c: show tab completions
     --version, -v: print version
        --help, -h: show help
EOS


DEF_CONFIG = <<-EOS
bookmarks: null
searcher:  https://duckduckgo.com/?q=
EOS


COMPLETION = <<-EOS
#compdef web
#autoload


_web_bookmarks() {
    #http://zsh.sourceforge.net/Guide/zshguide06.html#l147
    setopt glob bareglobqual nullglob rcexpandparam extendedglob automenu
    unsetopt allexport aliases errexit octalzeroes ksharrays cshnullglob

    #get chrome bookmarks
    local -a bookmarks sites search

    #grab all CLI args, remove 'web' from start
    search=`echo $@ | sed -e '/^web /d'`
    sites=`web --complete $search`
    bookmarks=("${(f)${sites}}")

    #terminal colors
    BLUE=`echo -e "\033[4;34m"`
    RESET=`echo -e "\033[0;0m"`

    #parse parts, color
    local -a ids links
    for bookmark in ${bookmarks[@]}; do
        local -a split
        split=("${(@s/:/)bookmark}")
        ids+=( $split[1] )
        links+=("$split[2] $BLUE$split[3]$RESET")
    done

    #finally, add completions
    compstate[insert]=menu
    compadd -U -l -X 'found chrome bookmarks:' -d links -a ids
}


_web() {
    compstate[insert]=menu
    local curcontext state line
    typeset -A opt_args
    _arguments\
        '(--search)--search[search google for...]'\
        '(-s)-s[search google for...]'\
        '(--bookmark)--bookmark[bookmark completion]'\
        '(-b)-b[bookmark completion]'\
        '*::bookmarks:->bookmarks' && return 0

    bm_query=$words
    _web_bookmarks $bm_query
}


_web
EOS


ZSH_SCRIPT = <<-EOS
# load zsh web completions
install_loc=~/.oh-my-zsh/completions
script=_web

install:
	mkdir -vp $(install_loc)
	cp -v $(script) $(install_loc)/

uninstall:
	rm -v $(install_loc)/$(script)
EOS
