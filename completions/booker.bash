# bash completion for booker
#
# Candidates are bookmark URLs, not bookmark ids. bash has no per-candidate
# descriptions (unlike zsh and fish), so a menu of bare ids -- 0_1, 2_7, ... --
# would tell you nothing about what you are picking. booker opens a URL
# argument directly, so completing to one lands in the same place as
# completing to an id.
#
# Install with: booker --install bash

_booker() {
    local cur arg
    local -a search_terms=()

    cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()

    # flags complete against the option list, not against bookmarks
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-b --bookmark -i --install -s --search \
            -l --list -c --complete --complete-raw -v --version -h --help" -- "$cur"))
        return 0
    fi

    # everything typed so far, minus the command name, flags, any URL already
    # completed onto the line, and any bookmark id typed by hand
    for arg in "${COMP_WORDS[@]:1}"; do
        [[ -z "$arg" ]] && continue
        [[ "$arg" == -* ]] && continue
        # completion inserts URLs, so a scheme marks a previous pick rather
        # than something to search for
        [[ "$arg" == *://* ]] && continue
        # mirrors BOOKMARK_ID in lib/booker/cli.rb: safari ids are uuids
        [[ "$arg" =~ ^([0-9]+_[a-zA-Z0-9-]+|[0-9_]+)$ ]] && continue
        search_terms+=("$arg")
    done

    # --complete-raw prints one "id <tab> title <tab> url" per match, never
    # truncated. read -r into fields so URLs containing glob characters (?, *)
    # survive intact -- an unquoted $(...) would let bash try to expand them.
    local id title url
    while IFS=$'\t' read -r id title url; do
        [[ -n "$url" ]] && COMPREPLY+=("$url")
    done < <(booker --complete-raw "${search_terms[@]}" 2>/dev/null)

    # NOTE: deliberately not filtered through `compgen -W ... -- "$cur"`.
    # booker matches on bookmark title as well as URL, so a candidate often
    # does not start with what the user typed, and compgen would drop it.
    return 0
}

complete -F _booker booker
