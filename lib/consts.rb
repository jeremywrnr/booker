# file for large constant strings


HELP_BANNER = <<-EOS
Open browser:
    $ booker [option] [arguments]

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
---
:searcher:  https://google.com/?q=
:bookmarks: null
EOS


COMPLETION = <<-EOS
#compdef booker
#autoload


_booker_bookmarks() {
    #http://zsh.sourceforge.net/Guide/zshguide06.html#l147
    setopt glob bareglobqual nullglob rcexpandparam extendedglob automenu
    unsetopt allexport aliases errexit octalzeroes ksharrays cshnullglob

    #get chrome bookmarks
    local -a bookmarks sites search

    #grab all CLI args, remove 'booker' from start
    search=`echo $@ | sed -e '/^booker /d'`
    sites=`booker --complete $search`
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


_booker() {
    compstate[insert]=menu
    local curcontext state line
    typeset -A opt_args
    _arguments\
        '(-b)-b[do bookmark completion]'\
        '(--bookmark)--bookmark[do bookmark completion]'\
        '(-c)-c[show bookmark completions]'\
        '(--complete)--complete[show bookmark completions]'\
        '(-i)-i[perform installations (bookmarks, completion, config)]'\
        '(--install)--install[perform installations (bookmarks, completion, config)]'\
        '(-s)-s[search google for...]'\
        '(--search)--search[search google for...]'\
        '(-h)-h[show booker help]'\
        '(--help)--help[show booker help]'\
        '(-v)-v[show version]'\
        '(--version)--version[show version]'\
        '*::bookmarks:->bookmarks' && return 0

    _booker_bookmarks $words
}


_booker
EOS


ZSH_SCRIPT = <<-EOS
# load zsh booker completions
install_loc=~/.oh-my-zsh/completions
script=_booker

install:
  mkdir -vp $(install_loc)
  cp -v $(script) $(install_loc)/

uninstall:
  rm -v $(install_loc)/$(script)
EOS
