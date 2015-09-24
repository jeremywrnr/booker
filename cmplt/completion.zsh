_web_complete()
{
  local word completions
  word="$1"
  completions="$(web --complete "${word}")"
  reply=( "${(ps:\n:)completions}" )
}

compctl -K _web_complete web
