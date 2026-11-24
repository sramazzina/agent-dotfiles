#!/usr/bin/env bash
# PreToolUse guard for irreversible operations (see
# docs/superpowers/specs/2026-11-24-irreversible-ops-guard-design.md).
# Reads the hook JSON on stdin; prints an ask/deny decision on a match, nothing
# otherwise. It never prints "allow" and never exits 2. Pure text check: no
# network, no git/gh calls.
set -u

DECISION=none
REASON=""

# hit <ask|deny> <reason>: record a match; deny beats ask, first reason wins per level.
hit() {
  if [ "$1" = deny ] && [ "$DECISION" != deny ]; then DECISION=deny; REASON="$2"
  elif [ "$1" = ask ] && [ "$DECISION" = none ]; then DECISION=ask; REASON="$2"
  fi
}
ask() { hit ask "guard: $1 needs user confirmation"; }
deny() { hit deny "guard: $1 is blocked; ask the user to run it themselves with !"; }

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
}

# git_push <args after "push">
git_push() {
  local force=0 a rest dest
  local -a pos=() dests=()
  while [ $# -gt 0 ]; do
    a=$1; shift
    case $a in
      --force|--force-with-lease|--force-with-lease=*|--force-if-includes) force=1 ;;
      --repo|--push-option|--receive-pack|--exec) shift ;;
      --*) ;;
      -*) case $a in *f*) force=1 ;; esac
          case $a in *o) shift ;; esac ;;
      *) pos+=("$a") ;;
    esac
  done
  # pos[0] is the remote; the rest are refspecs
  local k
  for ((k = 1; k < ${#pos[@]}; k++)); do
    a=${pos[k]}
    case $a in +*) force=1; a=${a#+} ;; esac
    dest=${a##*:}
    dest=${dest#refs/heads/}
    dests+=("$dest")
  done
  if [ "$force" = 1 ]; then
    for dest in "${dests[@]+"${dests[@]}"}"; do
      case $dest in
        main|master) deny "force push to main/master"; return ;;
      esac
    done
  fi
  ask "git push"
}

# gh_api <args after "api">
gh_api() {
  local a method
  while [ $# -gt 0 ]; do
    a=$1; shift
    case $a in
      -X|--method) method=${1:-}; shift || true
        case ${method^^} in GET) ;; *) ask "gh api (mutating)"; return ;; esac ;;
      --method=*|-X?*) method=${a#--method=}; method=${method#-X}
        case ${method^^} in GET) ;; *) ask "gh api (mutating)"; return ;; esac ;;
      -f*|-F*|--field|--field=*|--raw-field|--raw-field=*|--input|--input=*)
        ask "gh api (mutating)"; return ;;
    esac
  done
}

# classify <depth> <words...>: one simple command.
classify() {
  local depth=$1; shift
  local -a w=("$@")
  local i=0 t base
  while :; do
    [ "$i" -lt "${#w[@]}" ] || return 0
    t=${w[i]}
    if [[ $t =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then i=$((i + 1)); continue; fi
    base=${t##*/}
    case $base in
      then|do|else|if|while|until|elif|'!'|'{'|time|nohup|command|builtin|exec) i=$((i + 1)) ;;
      env|sudo|xargs|stdbuf|timeout|nice)
        i=$((i + 1))
        while [ "$i" -lt "${#w[@]}" ]; do
          case ${w[i]} in
            -u|-g|-I|-n|-P|-L|-d|-E|-i|-o|-e) # options taking a separate value
              case $base:${w[i]} in
                env:-u|sudo:-u|sudo:-g|xargs:-*|nice:-n|stdbuf:-[ioe]) i=$((i + 2)) ;;
                *) i=$((i + 1)) ;;
              esac ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
          esac
        done
        [ "$base" = timeout ] && i=$((i + 1)) # the duration
        ;;
      *) break ;;
    esac
  done
  local prog=${w[i]##*/}
  local -a a=("${w[@]:i+1}")
  local j=0 n=${#a[@]} g1 g2 x

  case $prog in
    bash|sh|dash|zsh)
      for ((j = 0; j < n; j++)); do
        case ${a[j]} in
          -*c*) [[ ${a[j]} =~ ^-[a-zA-Z]*c[a-zA-Z]*$ ]] || continue
                if [ "$depth" -lt 4 ] && [ $((j + 1)) -lt "$n" ]; then scan "${a[j+1]}" $((depth + 1)); fi
                return 0 ;;
          -*) ;;
          *) return 0 ;;
        esac
      done ;;
    git)
      while [ "$j" -lt "$n" ]; do
        case ${a[j]} in
          -C|-c|--git-dir|--work-tree|--namespace) j=$((j + 2)) ;;
          --git-dir=*|--work-tree=*|--namespace=*|--no-pager|-P|--bare|--no-replace-objects) j=$((j + 1)) ;;
          *) break ;;
        esac
      done
      [ "${a[j]:-}" = push ] && git_push "${a[@]:j+1}" ;;
    gh)
      while [ "$j" -lt "$n" ]; do
        case ${a[j]} in
          -R|--repo|--hostname) j=$((j + 2)) ;;
          --repo=*|--hostname=*) j=$((j + 1)) ;;
          *) break ;;
        esac
      done
      g1=${a[j]:-}; g2=${a[j+1]:-}
      case "$g1 $g2" in
        "repo delete") deny "gh repo delete" ;;
        "pr merge") ask "gh pr merge" ;;
        "release create"|"release edit"|"release delete"|"release upload") ask "gh $g1 $g2" ;;
        "workflow run") ask "gh workflow run" ;;
        "secret set"|"secret delete"|"secret remove") ask "gh $g1 $g2" ;;
        "variable set"|"variable delete") ask "gh $g1 $g2" ;;
        "api "*) gh_api "${a[@]:j+1}" ;;
      esac ;;
    mvn|mvnw)
      for x in "${a[@]}"; do
        case $x in deploy|deploy:deploy) ask "mvn deploy"; break ;; esac
      done ;;
    docker)
      while [ "$j" -lt "$n" ]; do
        case ${a[j]} in -*) j=$((j + 1)) ;; *) break ;; esac
      done
      case "${a[j]:-} ${a[j+1]:-}" in "push "*|"image push") ask "docker push" ;; esac ;;
  esac
  return 0
}

# scan <command string> <depth>: quote-aware split into simple commands.
scan() {
  local s=$1 depth=$2
  local -a words=() hd=()
  local cur="" have=0 q="" c nx i=0 n=${#s} line d strip
  local hd_strip=()

  flush_word() { if [ "$have" = 1 ]; then words+=("$cur"); fi; cur=""; have=0; }
  flush_seg() { flush_word; if [ "${#words[@]}" -gt 0 ]; then classify "$depth" "${words[@]}"; fi; words=(); }

  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    nx=${s:i+1:1}
    if [ "$q" = "'" ]; then
      if [ "$c" = "'" ]; then q=""; else cur+=$c; fi
    elif [ "$q" = '"' ]; then
      if [ "$c" = '"' ]; then q=""
      elif [ "$c" = '\' ] && [ -n "$nx" ]; then cur+=$nx; i=$((i + 1))
      else cur+=$c; fi
    else
      case $c in
        "'") q="'"; have=1 ;;
        '"') q='"'; have=1 ;;
        '\') if [ "$nx" = $'\n' ]; then i=$((i + 1)); elif [ -n "$nx" ]; then cur+=$nx; have=1; i=$((i + 1)); fi ;;
        ' '|$'\t') flush_word ;;
        '#') if [ "$have" = 0 ]; then
               while [ $((i + 1)) -lt "$n" ] && [ "${s:i+1:1}" != $'\n' ]; do i=$((i + 1)); done
             else cur+=$c; fi ;;
        ';'|'|'|'('|')'|'`') flush_seg ;;
        '&') # keep redirections like 2>&1, >&2 and &> inside the word
             if [ "${cur: -1}" = '>' ] || [ "${cur: -1}" = '<' ] || [ "$nx" = '>' ]; then cur+=$c; have=1
             else flush_seg; fi ;;
        '<') if [ "$nx" = '<' ] && [ "${s:i+2:1}" != '<' ]; then
               # heredoc: read the delimiter word, queue it
               i=$((i + 2)); strip=0
               if [ "${s:i:1}" = '-' ]; then strip=1; i=$((i + 1)); fi
               while [ "${s:i:1}" = ' ' ] || [ "${s:i:1}" = $'\t' ]; do i=$((i + 1)); done
               d=""
               while [ "$i" -lt "$n" ]; do
                 case ${s:i:1} in
                   ' '|$'\t'|$'\n'|';'|'&'|'|'|'('|')') break ;;
                   "'"|'"') ;;
                   *) d+=${s:i:1} ;;
                 esac
                 i=$((i + 1))
               done
               i=$((i - 1))
               hd+=("$d"); hd_strip+=("$strip")
             else cur+=$c; have=1; fi ;;
        $'\n') flush_seg
               # skip heredoc bodies up to their terminators
               local k
               for ((k = 0; k < ${#hd[@]}; k++)); do
                 while [ $((i + 1)) -lt "$n" ]; do
                   line=${s:i+1}; line=${line%%$'\n'*}
                   i=$((i + ${#line} + 1))
                   [ "${hd_strip[k]}" = 1 ] && line=${line##$'\t'}
                   [ "$line" = "${hd[k]}" ] && break
                 done
               done
               hd=(); hd_strip=() ;;
        *) cur+=$c; have=1 ;;
      esac
    fi
    i=$((i + 1))
  done
  flush_seg
}

main() {
  local input tool cmd
  input=$(cat) || return 0
  if ! command -v jq >/dev/null 2>&1 || ! jq -e . >/dev/null 2>&1 <<<"$input"; then
    emit ask "guard: hook error, confirm manually"
    return 0
  fi
  tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || tool=""
  [ "$tool" = Bash ] || return 0
  cmd=$(jq -r 'if (.tool_input.command|type)=="string" then .tool_input.command else "" end' <<<"$input" 2>/dev/null) || cmd=""
  [ -n "$cmd" ] || return 0
  scan "$cmd" 0
  if [ "$DECISION" != none ]; then emit "$DECISION" "$REASON"; fi
  return 0
}

main
exit 0
