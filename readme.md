cli google chrome bookmark parser
=================================

[![Build Status](https://travis-ci.org/jeremywrnr/booker.svg?branch=master)](https://travis-ci.org/jeremywrnr/booker)
[![MIT](https://img.shields.io/npm/l/alt.svg?style=flat)](http://mit-license.org)

## installing

    $ [sudo] gem install booker


## autcompletion
To load or reload the web completion script, run this command in `/completion`:

    $ make && unfunction _web && autoload -U _web


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
documentation out there on it. Probably 80% of the initial development time was
spent trying to figure out how to cycle through different matches...


## todo
- refactor so title is min(terminal width, max(message lengths))
- ~~make completion script read on gem install~~
- add option for dumping completion script, user can route to `$FPATH/_web`
- implement more testing with rspec
- config: browser, user, search
