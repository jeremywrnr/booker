# :bookmark: booker

[![CI](https://github.com/jeremywrnr/booker/actions/workflows/ci.yml/badge.svg)](https://github.com/jeremywrnr/booker/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fjeremywrnr.com%2Fbooker%2Fbadge-coverage.json)](https://jeremywrnr.com/booker/coverage/)
[![Gem](https://img.shields.io/gem/v/booker)](https://rubygems.org/gems/booker)
[![MIT](https://img.shields.io/badge/license-MIT-blue)](http://jeremywrnr.com/mit-license)

a CLI bookmark manager for Chrome, Firefox, and Safari, with tab completion for
zsh, bash, and fish.

![Screencast](assets/screencast.gif)


## setup

    [sudo] gem install booker
    booker --install

Alternatively, the installation can be done incrementally:

    booker -i comp # adding tab completion (every shell found)
    booker -i conf # generate default config (~/.booker.yml)
    booker -i book # locating bookmarks file

`booker -i comp` installs completion for every supported shell it finds on your
machine. To set up just one:

    booker -i zsh  # ~/.zsh/completion/_booker (or any writable $fpath dir)
    booker -i bash # ~/.local/share/bash-completion/completions/booker
    booker -i fish # ~/.config/fish/completions/booker.fish


## :bookmark: `booker` usage

##### picking a bookmark

    booker                  # choose from every bookmark
    booker [search_term]    # choose from the bookmarks matching a term

##### bookmark completion

    booker [your_search_term]<TAB>

##### opening a website

    booker github.com/jeremywrnr/booker

##### using a search engine

    booker how to use the internet


## the interactive picker

If [fzf](https://github.com/junegunn/fzf) is on your `PATH`, `booker` and `booker
<search>` open a fuzzy picker over the matching bookmarks and open whichever you
choose. `Tab` marks several to open at once; `Esc` cancels and does nothing.

The picker only appears when booker is talking to a terminal on both ends, so
pipes (`booker --complete-raw | ...`), scripts, and the tab completion subshells
all behave exactly as they did before. Without fzf installed the picker never
engages either: `booker` prints its table and `booker <search>` searches, as
always. Nothing here changes tab completion.

A search term that matches no bookmark still goes to your search engine, which is
why `booker how to use the internet` keeps working. To search for something that
*does* match a bookmark, ask for it explicitly with `booker -s <term>`. To get the
plain table back when fzf is installed, use `booker --list`.


## about
This is a tool that allows you to tab complete Chrome, Firefox,
and Safari bookmarks, and then open them in the browser of your choice. Chrome
stores bookmarks in a JSON file, Firefox uses a SQLite database, and Safari
uses a binary plist. Booker can read and parse all three formats, and can even
search across multiple bookmark sources simultaneously. Combined with an autocompletion mechanism (using a zsh
script), you can easily open your bookmarks from the command line.

I was inspired by the `kill` autocompletion that ships with oh-my-zsh, where
you are shown a list of the current processes, and you can tab through to
select which one you'd like to kill. The completion actually is somewhat
complex - if I search for 'System', it will only show processes whose name or
group match against that, but it tab through these matches numeric process IDs,
which is the argument that `kill` actually takes. I learned that zsh
autocompletion has a large learning curve, despite the good amount of
documentation out there on it.


## config
You can also edit the `~/.booker.yml` config file manually.
booker will also try to determine which command should be used to open your
browser based on your operating system, but you can also explicitly choose
which command you want use, by adding the following:

    :browser: 'your-browser-command '

To use something other than fzf for the interactive picker, name it with its
flags. booker splits this itself rather than handing it to a shell, and expects
the tool to read candidates on stdin and print the chosen ones on stdout:

    :picker: 'sk --height=40% --reverse'

Note that a config file naming `:picker:` cannot be read by a version of booker
older than this one - booker refuses to start on config keys it does not know.

## development / testing
There are some tests in `/spec`. If you clone this repo you can run them with
`just spec`. There is also a justfile to build and install the gem locally, so
you can run `just build` to build the gem.

`just cov` runs the suite with coverage, which is held at 100% - the report it
writes is published to [the coverage
page](https://jeremywrnr.com/booker/coverage/). `just docs` builds that
page together with this readme into `site/`, exactly as the Pages workflow does
on a merge to main, so `just docs-open` shows you what will deploy.

The completion scripts live in `/completions` (`_booker` for zsh, `booker.bash`,
`booker.fish`) and are read by `booker --install` at install time. They all feed
off `booker --complete-raw`, which prints one tab separated `id`, `title`, `url`
per match - unlike `--complete`, that output is never truncated or padded to the
terminal width, so a script can parse it safely.

All three shells complete to the bookmark's url, which booker opens directly.
zsh and fish also show the folder and title alongside each candidate; bash has
no per-candidate descriptions, so it shows the urls alone. Completing to the url
rather than to the bookmark id means the command line says what it is about to
open, and `2_D0EE60F9-3910-4466-8B03-B7FE74C90803` said nothing.

Bookmark ids still work as arguments - `booker 1_1017`, and `booker --bookmark`
- so anything scripted against them keeps running.

To reload a script you are editing:

    booker --install zsh && unfunction _booker && autoload -U _booker
    booker --install bash && source ~/.bashrc
    booker --install fish && exec fish
