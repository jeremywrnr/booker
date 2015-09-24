_web_complete()
{
  COMPREPLY=()
  local word="${COMP_WORDS[COMP_CWORD]}"
  local completions="$(web --cmplt "$word")"
  COMPREPLY=( $(compgen -W "$completions" -- "$word") )
}

complete -f -F _web_complete web
