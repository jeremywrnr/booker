# fish completion for booker
#
# fish shows a description next to each candidate, so -- like zsh, and unlike
# bash -- this completes to the bookmark id and puts the folder, title and URL
# in the description.
#
# Install with: booker --install fish

function __booker_bookmarks --description 'list booker bookmarks matching the current commandline'
    set -l tokens (commandline -poc) (commandline -ct)

    # drop the command name itself
    set -e tokens[1]

    # keep the search terms: no flags, no already-selected bookmark ids
    set -l terms
    for arg in $tokens
        test -z "$arg"; and continue
        string match -qr '^-' -- $arg; and continue
        # mirrors BOOKMARK_ID in lib/booker/cli.rb: safari ids are uuids
        string match -qr '^([0-9]+_[a-zA-Z0-9-]+|[0-9_]+)$' -- $arg; and continue
        set -a terms $arg
    end

    # --complete-raw prints "id <tab> title <tab> url"; fish wants
    # "value <tab> description", so fold the last two fields together
    booker --complete-raw $terms 2>/dev/null | while read -l -d \t id title url
        printf '%s\t%s %s\n' $id $title $url
    end
end

complete -c booker -f -a '(__booker_bookmarks)'

complete -c booker -s b -l bookmark -d 'explicitly open bookmark'
complete -c booker -s s -l search -d 'explicitly search arguments'
complete -c booker -s c -l complete -d 'show tab completions'
complete -c booker -s v -l version -d 'print version'
complete -c booker -s h -l help -d 'show help'
# the shell names here mirror SHELLS in lib/booker/installer.rb, which is the source of
# truth - add a shell there and it needs adding here too
complete -c booker -s i -l install -x -d 'install booker support files' \
    -a 'all bookmarks completion config safari zsh bash fish'
