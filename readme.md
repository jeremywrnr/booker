:bookmark: booker
=================


a CLI chrome bookmark parser, with tab completion.

[![Gem Version](https://badge.fury.io/rb/booker.svg)](https://badge.fury.io/rb/booker)
[![Build Status](https://travis-ci.org/jeremywrnr/booker.svg?branch=master)](https://travis-ci.org/jeremywrnr/booker)
[![MIT](https://img.shields.io/npm/l/alt.svg?style=flat)](http://jeremywrnr.com/mit-license)

![Screencast](http://i.imgur.com/yydqb3m.gif)


## setup

    $ [sudo] gem install booker

##### locating bookmarks

    $ booker -i book

##### tab completion (ZSH only)

    $ booker -i comp

##### generate default config (~/.booker.yml)

    $ booker -i conf


## :bookmark: `booker` usage

##### bookmark completion

    $ booker [your_search_term]<TAB>

##### opening a website

    $ booker github.com/jeremywrnr/booker

##### using a search engine

    $ booker how to use the internet


## about
This is a tool that allows you to tab complete (in zsh only) google chrome (gc)
bookmarks, and then open them in the browser of your choice. gc stores the
users bookmarks in a large json file locally, so this can be read/parsed by the
tool, and combined with an autocompletion mechanism (i used a zsh script, in
completion) to easily open your bookmarks from the command line.

I was inspired by the `kill` autocompletion that ships with oh-my-zsh, where
you are shown a list of the current processes, and you can tab through to
select which one you'd like to kill. The completion actually is somewhat
complex - if I search for 'System', it will only show processes whose name or
group match against that, but it tab through these matches numeric process IDs,
which is the argument that `kill` actually takes. I learned that zsh
autocompletion has a large learning curve, despite the good amount of
documentation out there on it.


## config
You can edit the `~/.booker.yml` config file, which will look something similar
to this:

    ---
    :searcher: https://google.com/?q=
    :bookmarks: "/Users/jeremywrnr/Library/Application Support/Google/Chrome/Profile 2/Bookmarks"

booker will also try to determine which command should be used to open your
browser based on your operating system, but you can also explicitly choose
which command you want use, by adding the following:

    :browser: '<your-command> '

## development / testing
There are some tests in `/spec`. If you clone this repo you can run them with
`rake`. There is also a Makefile to install the gem, so you can run `make` and
that will build the gem locally. To develop the zsh completion script, clone
this repo, and run this command in `/completion`:

    $ make && unfunction _booker && autoload -U _booker


## todos
- config: browser selection command
- add completion for -i/--install
- implement more rspec testing
- tell user when -i book fails
- parse all args, then if num open bookmark
- support opening multiple bookmarks: 1 1 1

