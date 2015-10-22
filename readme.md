:bookmark: booker
=================


[![Gem Version](https://badge.fury.io/rb/booker.svg)](https://badge.fury.io/rb/booker)
[![Build Status](https://travis-ci.org/jeremywrnr/booker.svg?branch=master)](https://travis-ci.org/jeremywrnr/booker)
[![MIT](https://img.shields.io/npm/l/alt.svg?style=flat)](http://mit-license.org)


a CLI chrome bookmark parser, with tab completion.


## setup

    $ [sudo] gem install booker

##### locating bookmarks

    $ web -i book

##### tab completion (ZSH only)

    $ web -i comp

##### generate default config (~/.booker.yml)

    $ web -i conf


## :bookmark: `web` usage

##### bookmark completion

    $ web [your_search_term]<TAB>

##### opening a website

    $ web github.com/jeremywrnr/booker

##### using a search engine

    $ web how to use the internet


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


## development / testing
There are some tests in `/spec`. If you clone this repo you can run them with
`rake`. There is also a Makefile to install the gem, so you can run `make` and
that will build the gem locally. To develop the zsh completion script, clone
this repo, and run this command in `/completion`:

    $ make && unfunction _web && autoload -U _web


## todos
- config: browser selection command
- add completion for -i/--install
- implement more rspec testing
- tell user when -i book fails
