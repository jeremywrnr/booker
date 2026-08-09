# fish completion for booker
#
# Candidates are bookmark URLs, matching zsh and bash. booker opens a URL
# argument directly, so this lands in the same place a bookmark id would, and
# the command line says what it is about to open. fish shows a description next
# to each candidate, so the folder and title go there.
#
# Install with: booker --install fish

function __booker_bookmarks --description 'list booker bookmarks matching the current commandline'
    set -l tokens (commandline -poc) (commandline -ct)

    # drop the command name itself
    set -e tokens[1]

    # keep the search terms: no flags, no already-completed URLs, no bookmark
    # ids typed by hand
    set -l terms
    for arg in $tokens
        test -z "$arg"; and continue
        string match -qr '^-' -- $arg; and continue
        # completion inserts URLs, so a scheme marks a previous pick
        string match -qr '://' -- $arg; and continue
        # mirrors BOOKMARK_ID in lib/booker/cli.rb: safari ids are uuids
        string match -qr '^([0-9]+_[a-zA-Z0-9-]+|[0-9_]+)$' -- $arg; and continue
        set -a terms $arg
    end

    # --complete-raw prints "id <tab> title <tab> url"; fish wants
    # "value <tab> description", so complete to the url and describe it with
    # the folder and title
    booker --complete-raw $terms 2>/dev/null | while read -l -d \t id title url
        printf '%s\t%s\n' $url $title
    end
end

complete -c booker -f -a '(__booker_bookmarks)'

complete -c booker -s b -l bookmark -d 'explicitly open bookmark'
complete -c booker -s s -l search -d 'explicitly search arguments'
complete -c booker -s l -l list -d 'print the bookmark table, skipping the picker'
complete -c booker -s c -l complete -d 'show tab completions'
complete -c booker -l complete-raw -d 'tab completions, tab separated (for shell scripts)'
complete -c booker -s v -l version -d 'print version'
complete -c booker -s h -l help -d 'show help'
# the shell names here mirror SHELLS in lib/booker/installer.rb, which is the source of
# truth - add a shell there and it needs adding here too
complete -c booker -s i -l install -x -d 'install booker support files' \
    -a 'all bookmarks completion config safari zsh bash fish'
