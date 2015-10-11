cli google chrome bookmark parser
=================================


This is a tool that allows you to tab complete (in zsh only) google chrome (gc)
bookmarks, and then open them in the browser of your choice. gc stores the
users bookmarks in a large json file locally, so this can be read/parsed by the
tool, and combined with an autocompletion


I was inspired by the `kill` autocompletion that ships with oh-my-zsh, where
you are shown a list of the current processes, and you can tab through to
select which one you'd like to kill. The completion actually is somewhat
complex - if I search for 'System', it will only show processes whose name or
group match against that, but it tab through these matches numeric process IDs,
which is the argument that `kill` actually takes. I learned that zsh
autocompletion has a large learning curve, despite the good amount of
documentation out there on it.


## todo

- refactor autocompletion so that the title it is the min of the terminal width,
and the max of the message lengths
- color link, and only match on title - path is good enough



## autcompletion

To load or reload the web completion script, run this command in `/completion`:

    make && unfunction _web && autoload -U _web

