#!/usr/bin/env bash
# PreToolUse guard for irreversible operations (see
# docs/superpowers/specs/2026-11-24-irreversible-ops-guard-design.md).
# Reads the hook JSON on stdin; prints an ask/deny decision on a match, nothing
# otherwise. It never prints "allow" and never exits 2. No network; the only
# git calls are local and read-only (rev-parse, config, log) for push decisions
# (see docs/superpowers/specs/2026-11-24-push-policy-design.md).
set -u
# Byte-wise string indexing: avoids multibyte overhead on long commands.
export LC_ALL=C

# Above this size the tokenizer is skipped (it is quadratic in bash) and a
# cheap conservative keyword check runs instead; it can only ask, never deny.
MAX_PARSE_BYTES=8192

DECISION=none
REASON=""
CWD=""
PERMISSION_MODE=""

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

# docs_only <dir> <remote> <dest> <src>: true when the outgoing commits
# (remote/dest..src) change only README.md, CLAUDE.md, CHANGELOG.md (repo root)
# or docs/HANDOFF*.md. Any git failure or an empty list means "not docs-only".
docs_only() {
  local dir=$1 remote=$2 dest=$3 src=$4 files p
  [ -n "$dir" ] && [ -n "$src" ] || return 1
  case $src in -*) return 1 ;; esac
  # -m lists merge commits' files too; --no-renames shows both sides of a rename.
  files=$(git -C "$dir" log -m --no-renames --name-only --format= "$remote/$dest..$src" -- 2>/dev/null) || return 1
  [ -n "$files" ] || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case $p in
      README.md|CLAUDE.md|CHANGELOG.md) ;;
      docs/HANDOFF*/*) return 1 ;;
      docs/HANDOFF*.md) ;;
      *) return 1 ;;
    esac
  done <<<"$files"
  return 0
}

# git_push <dir> <args after "push">: <dir> is the repository directory the
# push runs in; empty means it cannot be resolved (treated as protected).
# Decision rules: spec 2026-11-24-push-policy-design.md section 5.1.
git_push() {
  local dir=$1; shift
  local force=0 del=0 multi=0 a repo="" remote="" dest src cur="" k need_cur=0 prot=0 isdel
  local -a pos=() refs=() dsts=() srcs=()
  while [ $# -gt 0 ]; do
    a=$1; shift
    case $a in
      --force|--force-with-lease|--force-with-lease=*|--force-if-includes) force=1 ;;
      --delete) del=1 ;;
      --tags|--all|--mirror) multi=1 ;;
      --repo) repo=${1:-}; shift || true ;;
      --repo=*) repo=${a#--repo=} ;;
      --push-option|--receive-pack|--exec) shift ;;
      --*) ;;
      -*) case $a in *f*) force=1 ;; esac
          case $a in *d*) del=1 ;; esac
          case $a in *o) shift ;; esac ;;
      *) pos+=("$a") ;;
    esac
  done
  if [ -n "$repo" ]; then remote=$repo; refs=("${pos[@]+"${pos[@]}"}")
  elif [ "${#pos[@]}" -gt 0 ]; then remote=${pos[0]}; refs=("${pos[@]:1}"); fi
  [ "$multi" = 1 ] && prot=1
  [ -n "$dir" ] || prot=1

  for a in "${refs[@]+"${refs[@]}"}"; do
    isdel=$del
    case $a in +*) force=1; a=${a#+} ;; esac
    case $a in :*) isdel=1 ;; esac
    case $a in
      *:*) src=${a%%:*}; dest=${a##*:} ;;
      *) src=$a; dest=$a ;;
    esac
    [ "$isdel" = 1 ] && src=""
    dest=${dest#refs/heads/}
    case $dest in
      main|master) if [ "$force" = 1 ] || [ "$isdel" = 1 ]; then deny "force push or deletion of main/master"; return; fi ;;
      ''|*[\$\*\?\[\`]*) prot=1 ;;  # empty or unresolvable (variable, glob)
    esac
    [ "$dest" = HEAD ] || [ "$src" = HEAD ] && need_cur=1
    dsts+=("$dest"); srcs+=("$src")
  done
  [ "${#refs[@]}" -eq 0 ] && need_cur=1
  [ -z "$remote" ] && need_cur=1

  if [ "$need_cur" = 1 ]; then
    if [ -n "$dir" ]; then cur=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || cur=""; fi
    [ "$cur" = HEAD ] && cur=""   # detached
    [ -n "$cur" ] || prot=1
  fi
  if [ -z "$remote" ]; then
    if [ -n "$cur" ]; then
      remote=$(git -C "$dir" config "branch.$cur.pushRemote" 2>/dev/null) ||
        remote=$(git -C "$dir" config "branch.$cur.remote" 2>/dev/null) ||
        remote=$(git -C "$dir" config remote.pushDefault 2>/dev/null) || remote=""
    fi
    [ -n "$remote" ] || remote=origin
  fi
  if [ "${#refs[@]}" -eq 0 ]; then
    dest=$cur
    case $(git -C "${dir:-.}" config push.default 2>/dev/null) in
      upstream|tracking) # pushes to the tracking branch, whatever its name
        dest=$(git -C "$dir" config "branch.$cur.merge" 2>/dev/null) || dest=""
        dest=${dest#refs/heads/}; [ -n "$dest" ] || prot=1 ;;
    esac
    dsts=("$dest"); srcs=("$cur")
    [ -n "$dest" ] || prot=1
  fi
  [ "$remote" = upstream ] && prot=1

  for ((k = 0; k < ${#dsts[@]}; k++)); do
    dest=${dsts[k]}; src=${srcs[k]}
    [ "$dest" = HEAD ] && dest=$cur
    [ "$src" = HEAD ] && src=$cur
    case $dest in
      main|master)
        if [ "$force" = 1 ]; then deny "force push to main/master"; return; fi
        docs_only "$dir" "$remote" "$dest" "$src" || prot=1 ;;
    esac
  done
  if [ "$prot" = 1 ] && [ "$PERMISSION_MODE" != auto ]; then ask "git push"; fi
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
            -u|-g|-I|-n|-P|-L|-d|-E|-i|-o|-e|-s|-k|--signal|--kill-after) # options taking a separate value
              case $base:${w[i]} in
                env:-u|sudo:-u|sudo:-g|xargs:-*|nice:-n|stdbuf:-[ioe]|timeout:-s|timeout:-k|timeout:--signal|timeout:--kill-after) i=$((i + 2)) ;;
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
      local gdir=$CWD
      while [ "$j" -lt "$n" ]; do
        case ${a[j]} in
          -C) x=${a[j+1]:-}
              case $x in /*) gdir=$x ;; *) gdir=${gdir:-.}/$x ;; esac
              j=$((j + 2)) ;;
          --git-dir|--work-tree) gdir=""; j=$((j + 2)) ;;
          --git-dir=*|--work-tree=*) gdir=""; j=$((j + 1)) ;;
          -c|--namespace) j=$((j + 2)) ;;
          --namespace=*|--no-pager|-P|--bare|--no-replace-objects) j=$((j + 1)) ;;
          *) break ;;
        esac
      done
      # no cwd in the input: fall back to the hook's own directory
      [ "${a[j]:-}" = push ] && git_push "$gdir" "${a[@]:j+1}" ;;
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
      # Note: pushes inside "$(...)" are not scanned here; Claude Code's own
      # ask rules cover command substitutions.
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
        '<') if [ "${s:i:3}" = '<<<' ]; then
               i=$((i + 2)) # herestring: plain redirect, no body
             elif [ "$nx" = '<' ]; then
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
  CWD=$(jq -r '.cwd // empty | strings' <<<"$input" 2>/dev/null) || CWD=""
  PERMISSION_MODE=$(jq -r '.permission_mode // empty | strings' <<<"$input" 2>/dev/null) || PERMISSION_MODE=""
  [ -n "$CWD" ] || CWD=.
  if [ "${#cmd}" -gt "$MAX_PARSE_BYTES" ]; then
    local sp='[[:space:]]'
    if [[ $cmd =~ (^|[^[:alnum:]_])git$sp.*push ]]; then
      # Not parsed: protected unless auto mode, where the classifier rules; a
      # visible force push to main/master still asks, as before.
      if [ "$PERMISSION_MODE" != auto ] ||
         { [[ $cmd =~ (--force|$sp-[a-zA-Z]*f|\+) ]] && [[ $cmd =~ (^|[^[:alnum:]_])(main|master)([^[:alnum:]_]|$) ]]; }; then
        ask "git push (oversized command)"
      fi
    elif [[ $cmd =~ (^|[^[:alnum:]_])gh$sp.*(pr${sp}+merge|release|repo${sp}+delete|workflow${sp}+run|secret|variable|api) ]]; then ask "gh (oversized command)"
    elif [[ $cmd =~ deploy ]]; then ask "deploy (oversized command)"
    elif [[ $cmd =~ (^|[^[:alnum:]_])docker$sp.*push ]]; then ask "docker push (oversized command)"
    fi
  else
    scan "$cmd" 0
  fi
  if [ "$DECISION" != none ]; then emit "$DECISION" "$REASON"; fi
  return 0
}

main
exit 0
