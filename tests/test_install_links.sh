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
  local ino; ino="$(stat -c %i "$HOME/.claude/skills/synced")"
  run_install
  assert_eq "x" "$(cat "$HOME/.claude/skills/synced/x")" "synced content"
  [ ! -L "$HOME/.claude/skills/synced" ] || fail "synced became a link"
  assert_eq "$ino" "$(stat -c %i "$HOME/.claude/skills/synced")" "synced inode"
  assert_not_contains "$OUT" "synced" "summary mentions synced"
  [ ! -e "$HOME/.agent-dotfiles-backups" ] || fail "synced was backed up"
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
  echo old > "$HOME/.claude/CLAUDE.md" 2>/dev/null || { mkdir -p "$HOME/.claude"; echo old > "$HOME/.claude/CLAUDE.md"; }
  run_install --dry-run
  assert_eq "old" "$(cat "$HOME/.claude/CLAUDE.md")" "real file kept in dry-run"
  [ ! -L "$HOME/.claude/CLAUDE.md" ] || fail "dry-run linked over real file"
  [ ! -e "$HOME/.agent-dotfiles-backups" ] || fail "dry-run created backup dir"
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

test_clone_at_anchor_location() {
  setup_home
  mkdir "$HOME/.agent-dotfiles"
  cp -a "$REPO_ROOT/install.sh" "$REPO_ROOT/agents" "$REPO_ROOT/rules" "$REPO_ROOT/skills" "$HOME/.agent-dotfiles/"
  set +e
  OUT="$(env PATH="$TEST_HOME/bin:$PATH" "$HOME/.agent-dotfiles/install.sh" 2>&1)"
  set -e
  [ -d "$HOME/.agent-dotfiles" ] && [ ! -L "$HOME/.agent-dotfiles" ] || fail "anchor not a real dir"
  [ -f "$HOME/.agent-dotfiles/install.sh" ] || fail "repo damaged"
  assert_contains "$OUT" "unchanged: $HOME/.agent-dotfiles" "anchor"
  [ ! -e "$HOME/.agent-dotfiles-backups" ] || fail "repo was backed up"
  assert_symlink_to "$HOME/.claude/CLAUDE.md" "$HOME/.agent-dotfiles/agents/claude/CLAUDE.md"
  [ -e "$HOME/.claude/rules/java.md" ] || fail "rule link dangles"
}

test_backups_never_collide() {
  setup_home
  export AGENT_DOTFILES_TS=20000101-000000
  mkdir -p "$HOME/.claude"
  echo one > "$HOME/.claude/CLAUDE.md"
  run_install
  rm "$HOME/.claude/CLAUDE.md"; echo two > "$HOME/.claude/CLAUDE.md"
  run_install
  local n; n="$(ls -d "$HOME"/.agent-dotfiles-backups/*/ | wc -l)"
  assert_eq "2" "$n" "backup dirs"
  assert_eq "one" "$(cat "$HOME/.agent-dotfiles-backups/20000101-000000/.claude/CLAUDE.md")" "first backup"
  assert_eq "two" "$(cat "$HOME/.agent-dotfiles-backups/20000101-000000-1/.claude/CLAUDE.md")" "second backup"
}
