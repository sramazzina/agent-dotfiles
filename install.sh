#!/usr/bin/env bash
# agent-dotfiles installer (Claude Code adapter). Idempotent; never installs prerequisites.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
DRY_RUN=0
FAILED=0
ENABLE_DEV_DIR=""
# AGENT_DOTFILES_TS overrides the backup timestamp (tests only).
BACKUP_TS="${AGENT_DOTFILES_TS:-$(date +%Y%m%d-%H%M%S)}"
BACKUP_DIR="$HOME/.agent-dotfiles-backups/$BACKUP_TS"
BACKUP_READY=0

usage() {
  cat <<'USAGE'
Usage:
  install.sh [--dry-run]                     full Claude Code install
  install.sh --enable-dev <dir> [--dry-run]  enable dev profile in one project
  install.sh --help
USAGE
}

log() {
  local prefix=""
  [ "$DRY_RUN" = 1 ] && prefix="DRY-RUN "
  printf '%s%s\n' "$prefix" "$*"
}

have() { command -v "$1" >/dev/null 2>&1; }

# Pick the run's backup dir once, lazily: never reuse a dir left by an earlier run.
init_backup_dir() {
  [ "$BACKUP_READY" = 1 ] && return 0
  local base="$BACKUP_DIR" n=0
  while [ -e "$BACKUP_DIR" ]; do
    n=$((n + 1)); BACKUP_DIR="$base-$n"
  done
  BACKUP_READY=1
}

# Move an existing file/dir/link into the run's backup dir, preserving its path relative to $HOME.
backup_path() {
  local path="$1" rel dest
  rel="${path#"$HOME"/}"
  init_backup_dir
  dest="$BACKUP_DIR/$rel"
  if [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$(dirname "$dest")"
    mv -n "$path" "$dest"
    if [ -e "$path" ] || [ -L "$path" ] || ! { [ -e "$dest" ] || [ -L "$dest" ]; }; then
      log "failed: backup of $path"
      FAILED=1
      return 1
    fi
  fi
  log "backed-up: $path -> $dest"
}

# Idempotent symlink: link_to <target> <source>. Existing non-matching entries are backed up first.
link_to() {
  local target="$1" source="$2"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    log "unchanged: $target"
    return 0
  fi
  # Never back up the clone itself (or anything inside it), e.g. a clone living at ~/.agent-dotfiles.
  if [ ! -L "$target" ] && [ -e "$target" ]; then
    case "$(readlink -f "$target")" in
      "$REPO_ROOT"|"$REPO_ROOT"/*) log "unchanged: $target"; return 0 ;;
    esac
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup_path "$target" || return 0
  fi
  if [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
  fi
  log "linked: $target"
}

check_prerequisites() {
  local tool
  for tool in git jq claude gh serena serena-hooks uvx node npx; do
    if ! have "$tool"; then
      log "missing: $tool"
      case "$tool" in jq|claude) FAILED=1 ;; esac
    fi
  done
  if [ "$DRY_RUN" = 1 ]; then
    return 0   # auth probes would touch claude/gh; the contract says dry-run leaves them alone
  fi
  if have gh && ! gh auth status >/dev/null 2>&1; then
    log "skipped: gh-auth (not logged in)"
  fi
  if have claude && ! claude auth status >/dev/null 2>&1; then
    log "skipped: claude-auth (not logged in)"
  fi
}

link_all() {
  local f d name
  link_to "$HOME/.agent-dotfiles" "$REPO_ROOT"
  link_to "$HOME/.claude/CLAUDE.md" "$REPO_ROOT/agents/claude/CLAUDE.md"
  link_to "$HOME/.claude/profiles/dev.md" "$REPO_ROOT/agents/claude/dev.md"
  # Rules: symlink mode (decided in docs/verification.md); copy mode is not implemented.
  for f in "$REPO_ROOT"/rules/*.md; do
    [ -e "$f" ] || continue
    link_to "$HOME/.claude/rules/$(basename "$f")" "$f"
  done
  for d in "$REPO_ROOT"/skills/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    link_to "$HOME/.claude/skills/$name" "$REPO_ROOT/skills/$name"
  done
}

# Report (never delete) links into this clone whose source no longer exists.
scan_stale() {
  local l t
  for l in "$HOME"/.claude/rules/* "$HOME"/.claude/skills/*; do
    [ -L "$l" ] || continue
    t="$(readlink "$l")"
    case "$t" in
      "$REPO_ROOT"/*) [ -e "$l" ] || log "stale: $l" ;;
    esac
  done
}

# Copy (not move) an existing file into the run's backup dir; the original stays until replaced.
copy_to_backup() {
  local path="$1" rel dest
  rel="${path#"$HOME"/}"
  init_backup_dir
  dest="$BACKUP_DIR/$rel"
  if [ "$DRY_RUN" = 0 ]; then
    if ! { mkdir -p "$(dirname "$dest")" && cp -p "$path" "$dest"; }; then
      log "failed: backup of $path"
      FAILED=1
      return 1
    fi
  fi
  log "backed-up: $path -> $dest"
}

# Merge agents/claude/settings.fragment.json into ~/.claude/settings.json.
# enforce keys always win (hooks replaced as a whole); seed keys only when absent.
merge_settings() {
  local frag="$REPO_ROOT/agents/claude/settings.fragment.json"
  local target="$HOME/.claude/settings.json" local_json merged tmp mode k
  if ! have jq; then
    log "skipped: settings (jq missing)"
    FAILED=1
    return 0
  fi
  # Write through a symlinked settings.json so the user's link survives.
  if [ -L "$target" ]; then
    if [ ! -e "$target" ]; then
      log "failed: settings (dangling symlink $target)"
      FAILED=1
      return 0
    fi
    target="$(readlink -f "$target")"
  fi
  local_json="{}"
  if [ -e "$target" ]; then
    if ! jq -e 'type == "object"' "$target" >/dev/null 2>&1; then
      log "failed: settings (invalid JSON in $target; left untouched)"
      FAILED=1
      return 0
    fi
    local_json="$(cat "$target")"
  fi
  merged="$(jq -n --argjson l "$local_json" --slurpfile f "$frag" '
    $f[0] as $f
    | (($l * ($f.enforce | del(.hooks))) | .hooks = $f.enforce.hooks) as $m
    | reduce ($f.seed | keys[]) as $k ($m; if has($k) then . else .[$k] = $f.seed[$k] end)')" || {
    log "failed: settings (merge)"
    FAILED=1
    return 0
  }
  if [ "$(jq -S . <<<"$local_json")" = "$(jq -S . <<<"$merged")" ]; then
    log "unchanged: $target"
    return 0
  fi
  while IFS= read -r k; do
    log "changed: settings.$k"
  done < <(jq -rn --argjson l "$local_json" --argjson m "$merged" --slurpfile f "$frag" \
    '$f[0].enforce | keys[] | select($l[.] != $m[.])')
  while IFS= read -r k; do
    log "seeded: settings.$k"
  done < <(jq -rn --argjson l "$local_json" --slurpfile f "$frag" \
    '$f[0].seed | keys[] | . as $k | select($l | has($k) | not)')
  [ "$DRY_RUN" = 1 ] && { [ -e "$target" ] && copy_to_backup "$target"; return 0; }
  mode=600
  if [ -e "$target" ]; then
    mode="$(stat -c %a "$target")"
    copy_to_backup "$target" || return 0
  fi
  if ! mkdir -p "$(dirname "$target")"; then
    log "failed: settings (mkdir)"
    FAILED=1
    return 0
  fi
  if ! tmp="$(mktemp "$target.XXXXXX")"; then
    log "failed: settings (mktemp)"
    FAILED=1
    return 0
  fi
  if ! { printf '%s\n' "$merged" > "$tmp" && chmod "$mode" "$tmp"; }; then
    rm -f "$tmp"
    log "failed: settings (write)"
    FAILED=1
    return 0
  fi
  if ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    log "failed: settings (mv)"
    FAILED=1
    return 0
  fi
}

# Register user-scope MCP servers from mcp/servers.json (read-only compare against ~/.claude.json).
# Only type/url/command/args and header NAMES are read from the live config; values never are.
register_mcp() {
  local manifest="$REPO_ROOT/mcp/servers.json" cfg="$HOME/.claude.json"
  local tool name transport cur drift var hdr rc srv missing
  for tool in claude jq; do
    if ! have "$tool"; then
      log "skipped: mcp ($tool missing)"
      FAILED=1
      return 0
    fi
  done
  if [ -e "$cfg" ] && ! jq -e 'type == "object"' "$cfg" >/dev/null 2>&1; then
    log "failed: mcp (cannot read $cfg)"
    FAILED=1
    return 0
  fi
  while IFS= read -r srv; do
    name="$(jq -r .name <<<"$srv")"
    transport="$(jq -r .transport <<<"$srv")"
    cur=""
    [ -e "$cfg" ] && cur="$(jq -c --arg n "$name" '.mcpServers[$n] // empty | {type, url, command, args, headers: ((.headers // {}) | keys)}' "$cfg")"
    if [ -n "$cur" ]; then
      drift="$(jq -rn --argjson s "$srv" --argjson c "$cur" '
        [ (if ($c.type // "stdio") != $s.transport then "type" else empty end),
          (if $s.transport == "http" then
             (if $c.url != $s.url then "url" else empty end),
             (if ($c.headers | sort) != (($s.headers // {}) | keys | sort) then "headers" else empty end)
           else
             (if $c.command != $s.command then "command" else empty end),
             (if ($c.args // []) != ($s.agents.claude.args // $s.args // []) then "args" else empty end)
           end) ] | join(",")')"
      if [ -n "$drift" ]; then
        log "drift: mcp $name ($drift)"
      else
        log "mcp-ok: $name"
      fi
      continue
    fi
    # Absent: verify every referenced env var is set, then build argv piece by piece (no eval).
    local -a add=(claude mcp add --scope user)
    missing=""
    if [ "$transport" = http ]; then
      add+=(--transport http "$name" "$(jq -r .url <<<"$srv")")
      while IFS=$'\t' read -r hdr var; do
        [ -n "$hdr" ] || continue
        if [ -z "${!var:-}" ]; then missing="$var"; break; fi
        add+=(-H "$hdr: ${!var}")
      done < <(jq -r '(.headers // {}) | to_entries[] | [.key, .value.env] | @tsv' <<<"$srv")
    else
      add+=("$name" -- "$(jq -r .command <<<"$srv")")
      while IFS= read -r var; do add+=("$var"); done \
        < <(jq -r '(.agents.claude.args // .args // [])[]' <<<"$srv")
    fi
    if [ -n "$missing" ]; then
      log "skipped: mcp $name (env $missing unset)"
      FAILED=1
      continue
    fi
    if [ "$DRY_RUN" = 0 ]; then
      rc=0
      "${add[@]}" >/dev/null 2>&1 || rc=$?
      if [ "$rc" != 0 ]; then
        log "failed: mcp $name (claude mcp add exit $rc)"
        FAILED=1
        continue
      fi
    fi
    log "mcp-added: $name"
  done < <(jq -c '.servers[]' "$manifest")
}

# Opt one project into the dev profile: CLAUDE.local.md import + repo-local git exclude. Never commits.
enable_dev() {
  local dir="$1" file excl import='@~/.claude/profiles/dev.md'
  if [ ! -d "$dir" ]; then
    echo "not a directory: $dir" >&2
    exit 2
  fi
  file="$dir/CLAUDE.local.md"
  if [ ! -e "$file" ]; then
    [ "$DRY_RUN" = 1 ] || printf '%s\n' "$import" > "$file" || { log "failed: $file (write)"; FAILED=1; return 0; }
    log "created: $file"
  elif grep -qxF "$import" "$file"; then
    log "unchanged: $file"
  else
    if [ "$DRY_RUN" = 0 ]; then
      { [ ! -s "$file" ] || [ -z "$(tail -c1 "$file")" ] || printf '\n'; printf '%s\n' "$import"; } >> "$file" \
        || { log "failed: $file (append)"; FAILED=1; return 0; }
    fi
    log "appended: $file"
  fi

  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$dir" check-ignore -q CLAUDE.local.md; then
      log "unchanged: ignore (CLAUDE.local.md already ignored)"
    else
      excl="$(git -C "$dir" rev-parse --git-path info/exclude)"
      case "$excl" in /*) ;; *) excl="$dir/$excl" ;; esac
      if [ "$DRY_RUN" = 0 ]; then
        { mkdir -p "$(dirname "$excl")" \
          && { [ ! -s "$excl" ] || [ -z "$(tail -c1 "$excl")" ] || printf '\n' >> "$excl"; } \
          && printf '%s\n' 'CLAUDE.local.md' >> "$excl"; } \
          || { log "failed: $excl (write)"; FAILED=1; return 0; }
      fi
      log "appended: $excl"
    fi
  else
    log "skipped: ignore (not a git repo)"
  fi

  [ -e "$HOME/.claude/profiles/dev.md" ] || log "skipped: dev-profile-check (run install.sh first)"
  echo "First session in this project will ask to approve the external import — accept it."
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --enable-dev)
        [ $# -ge 2 ] || { usage >&2; exit 2; }
        ENABLE_DEV_DIR="$2"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done

  if [ -n "$ENABLE_DEV_DIR" ]; then
    enable_dev "$ENABLE_DEV_DIR"
    exit "$FAILED"
  fi

  check_prerequisites
  link_all
  scan_stale
  merge_settings
  register_mcp
  exit "$FAILED"
}

main "$@"
