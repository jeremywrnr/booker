# file for large constant strings


HELP_BANNER = <<-EOS
Open browser:
    $ web [options]
Options:
    --bookmark, -b: explicity open bookmark
      --search, -s: explicity open search
        --complete: show completions
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
EOS