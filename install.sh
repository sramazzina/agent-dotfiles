#!/usr/bin/env bash
# agent-dotfiles installer (Claude Code adapter). Idempotent; never installs prerequisites.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
DRY_RUN=0
FAILED=0
ENABLE_DEV_DIR=""
BACKUP_DIR=""

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

backup_dir() {
  [ -n "$BACKUP_DIR" ] || BACKUP_DIR="$HOME/.agent-dotfiles-backups/$(date +%Y%m%d-%H%M%S)"
  printf '%s' "$BACKUP_DIR"
}

# Move an existing file/dir/link into the run's backup dir, preserving its path relative to $HOME.
backup_path() {
  local path="$1" rel dest
  rel="${path#"$HOME"/}"
  dest="$(backup_dir)/$rel"
  if [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$(dirname "$dest")"
    mv "$path" "$dest"
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
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup_path "$target"
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
  # merge_settings (settings step) and register_mcp (MCP step) slot in here.
  exit "$FAILED"
}

main "$@"
