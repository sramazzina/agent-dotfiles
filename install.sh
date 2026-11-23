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

# Placeholder; replaced by the real implementation in a later task.
enable_dev() {
  log "skipped: enable-dev (not implemented)"
  FAILED=1
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
  # register_mcp (MCP step) slots in here.
  exit "$FAILED"
}

main "$@"
