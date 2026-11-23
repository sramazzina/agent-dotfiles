# Tests for install.sh prerequisites and linking (Task 3).

test_fresh_install_links() {
  setup_home
  run_install
  assert_symlink_to "$HOME/.agent-dotfiles" "$REPO_ROOT"
  assert_symlink_to "$HOME/.claude/CLAUDE.md" "$REPO_ROOT/agents/claude/CLAUDE.md"
  assert_symlink_to "$HOME/.claude/profiles/dev.md" "$REPO_ROOT/agents/claude/dev.md"
  assert_symlink_to "$HOME/.claude/rules/java.md" "$REPO_ROOT/rules/java.md"
  assert_symlink_to "$HOME/.claude/skills/serena-query-project" "$REPO_ROOT/skills/serena-query-project"
  assert_contains "$OUT" "linked: $HOME/.claude/CLAUDE.md" "summary"
}

test_rerun_is_noop() {
  setup_home
  run_install
  run_install
  assert_eq "0" "$(printf '%s\n' "$OUT" | grep -c '^linked:' || true)" "linked lines on rerun"
  assert_eq "0" "$(printf '%s\n' "$OUT" | grep -c '^backed-up:' || true)" "backed-up lines on rerun"
  assert_contains "$OUT" "unchanged: $HOME/.claude/CLAUDE.md" "unchanged"
  [ ! -e "$HOME/.agent-dotfiles-backups" ] || fail "backup dir created"
}

test_existing_real_files_backed_up() {
  setup_home
  mkdir -p "$HOME/.claude/skills/serena-query-project"
  echo old > "$HOME/.claude/CLAUDE.md"
  echo olds > "$HOME/.claude/skills/serena-query-project/SKILL.md"
  run_install
  assert_symlink_to "$HOME/.claude/CLAUDE.md" "$REPO_ROOT/agents/claude/CLAUDE.md"
  assert_symlink_to "$HOME/.claude/skills/serena-query-project" "$REPO_ROOT/skills/serena-query-project"
  local b
  b="$(ls -d "$HOME"/.agent-dotfiles-backups/*/)"
  assert_eq "old" "$(cat "$b/.claude/CLAUDE.md")" "backed-up file"
  assert_eq "olds" "$(cat "$b/.claude/skills/serena-query-project/SKILL.md")" "backed-up dir"
  assert_contains "$OUT" "backed-up: $HOME/.claude/CLAUDE.md -> " "summary"
}

test_synced_untouched() {
  setup_home
  mkdir -p "$HOME/.claude/skills/synced"
  echo x > "$HOME/.claude/skills/synced/x"
  run_install
  assert_eq "x" "$(cat "$HOME/.claude/skills/synced/x")" "synced content"
  [ ! -L "$HOME/.claude/skills/synced" ] || fail "synced became a link"
}

test_anchor_moved_clone() {
  setup_home
  ln -s /tmp/elsewhere "$HOME/.agent-dotfiles"
  run_install
  assert_symlink_to "$HOME/.agent-dotfiles" "$REPO_ROOT"
  assert_contains "$OUT" "backed-up: $HOME/.agent-dotfiles -> " "summary"
  assert_symlink_to "$(ls -d "$HOME"/.agent-dotfiles-backups/*/)/.agent-dotfiles" "/tmp/elsewhere"
}

test_stale_link_reported() {
  setup_home
  mkdir -p "$HOME/.claude/rules"
  ln -s "$REPO_ROOT/rules/gone.md" "$HOME/.claude/rules/gone.md"
  run_install
  assert_contains "$OUT" "stale: $HOME/.claude/rules/gone.md" "stale"
  [ -L "$HOME/.claude/rules/gone.md" ] || fail "stale link removed"
}

test_dry_run_changes_nothing() {
  setup_home
  local before after
  before="$(find "$HOME" | sort)"
  run_install --dry-run
  after="$(find "$HOME" | sort)"
  assert_eq "0" "$RC" "exit code"
  assert_eq "$before" "$after" "filesystem"
  [ -n "$OUT" ] || fail "no output"
  assert_eq "0" "$(printf '%s\n' "$OUT" | grep -vc '^DRY-RUN ' || true)" "lines without DRY-RUN prefix"
  assert_contains "$OUT" "DRY-RUN linked: $HOME/.claude/CLAUDE.md" "planned link"
}

test_runs_from_other_cwd() {
  setup_home
  cd /
  run_install
  assert_symlink_to "$HOME/.claude/CLAUDE.md" "$REPO_ROOT/agents/claude/CLAUDE.md"
  assert_symlink_to "$HOME/.agent-dotfiles" "$REPO_ROOT"
}

test_usage_error() {
  setup_home
  run_install --bogus
  assert_eq "2" "$RC" "exit code"
}
