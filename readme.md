# :bookmark: booker

[![Build Status](https://app.travis-ci.com/jeremywrnr/booker.svg)](https://app.travis-ci.com/jeremywrnr/booker)
[![MIT](https://img.shields.io/npm/l/alt.svg?style=flat)](http://jeremywrnr.com/mit-license)

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

##### bookmark completion

    booker [your_search_term]<TAB>

##### opening a website

    booker github.com/jeremywrnr/booker

##### using a search engine

    booker how to use the internet


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

## development / testing
There are some tests in `/spec`. If you clone this repo you can run them with
`just spec`. There is also a justfile to build and install the gem locally, so
you can run `just build` to build the gem.

The completion scripts live in `/completions` (`_booker` for zsh, `booker.bash`,
`booker.fish`) and are read by `booker --install` at install time. They all feed
off `booker --complete-raw`, which prints one tab separated `id`, `title`, `url`
per match - unlike `--complete`, that output is never truncated or padded to the
terminal width, so a script can parse it safely.

zsh and fish complete to the bookmark id and show the title and url as the
candidate's description. bash has no per-candidate descriptions, so it completes
to the url itself, which booker opens directly.

To reload a script you are editing:

    booker --install zsh && unfunction _booker && autoload -U _booker
    booker --install bash && source ~/.bashrc
    booker --install fish && exec fish
