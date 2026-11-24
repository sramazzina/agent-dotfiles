# Tests for the settings fragment merge (Task 4).

FRAG="$REPO_ROOT/agents/claude/settings.fragment.json"

test_settings_created_when_absent() {
  setup_home
  run_install
  S="$HOME/.claude/settings.json"
  [ -f "$S" ] || fail "settings not created"
  assert_file_mode "$S" 600
  assert_eq "true" "$(jq --slurpfile f "$FRAG" '(.statusLine == $f[0].enforce.statusLine) and (.hooks == $f[0].enforce.hooks) and (.model == $f[0].seed.model) and (.effortLevel == $f[0].seed.effortLevel) and (.env.CLAUDE_CODE_SUBAGENT_MODEL == "sonnet")' "$S")" "enforce+seed"
  assert_contains "$OUT" "changed: settings.hooks" "changed"
  assert_contains "$OUT" "seeded: settings.model" "seeded"
}

test_settings_preserves_unknown_keys() {
  setup_home
  mkdir -p "$HOME/.claude"
  echo '{"autoMode":{"x":1},"permissions":{"allow":["Bash(ls:*)"]},"env":{"FOO":"bar"},"enabledPlugins":{"other@x":true}}' > "$HOME/.claude/settings.json"
  run_install
  S="$HOME/.claude/settings.json"
  assert_eq "true" "$(jq '.autoMode.x == 1 and .permissions.allow == ["Bash(ls:*)"] and .env.FOO == "bar" and .enabledPlugins["other@x"] == true and .permissions.defaultMode == "auto" and .env.CLAUDE_CODE_SUBAGENT_MODEL == "sonnet" and .enabledPlugins["superpowers@superpowers-marketplace"] == true' "$S")" "preserved"
}

test_settings_seed_not_overwritten() {
  setup_home
  mkdir -p "$HOME/.claude"
  echo '{"model":"sonnet"}' > "$HOME/.claude/settings.json"
  run_install
  assert_eq "sonnet" "$(jq -r .model "$HOME/.claude/settings.json")" "model"
  assert_not_contains "$OUT" "seeded: settings.model" "no model seed"
  assert_contains "$OUT" "seeded: settings.effortLevel" "effort seeded"
}

test_settings_hooks_replaced() {
  setup_home
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{"PostToolUse":[{"matcher":"","hooks":[{"type":"command","command":"echo hi"}]}]}}' > "$HOME/.claude/settings.json"
  run_install
  assert_eq "true" "$(jq --slurpfile f "$FRAG" '.hooks == $f[0].enforce.hooks' "$HOME/.claude/settings.json")" "hooks"
}

test_settings_mode_preserved() {
  setup_home
  mkdir -p "$HOME/.claude"
  echo '{}' > "$HOME/.claude/settings.json"
  chmod 640 "$HOME/.claude/settings.json"
  run_install
  assert_file_mode "$HOME/.claude/settings.json" 640
  echo '{}' > "$HOME/.claude/settings.json"
  chmod 600 "$HOME/.claude/settings.json"
  run_install
  assert_file_mode "$HOME/.claude/settings.json" 600
}

test_settings_invalid_json() {
  setup_home
  mkdir -p "$HOME/.claude"
  printf '{not json' > "$HOME/.claude/settings.json"
  run_install
  assert_eq "1" "$RC" "exit code"
  assert_eq "{not json" "$(cat "$HOME/.claude/settings.json")" "file untouched"
  [ -z "$(find "$HOME/.agent-dotfiles-backups" -name settings.json 2>/dev/null)" ] || fail "unexpected settings backup"
}

test_settings_backup_on_change() {
  setup_home
  mkdir -p "$HOME/.claude"
  echo '{"model":"sonnet"}' > "$HOME/.claude/settings.json"
  run_install
  assert_contains "$OUT" "backed-up: $HOME/.claude/settings.json" "backup line"
  assert_eq '{"model":"sonnet"}' "$(cat "$HOME"/.agent-dotfiles-backups/*/.claude/settings.json)" "backup content"
}

test_settings_idempotent() {
  setup_home
  run_install
  run_install
  assert_eq "0" "$(printf '%s\n' "$OUT" | grep -c '^changed:\|^seeded:' || true)" "changed/seeded on rerun"
  assert_not_contains "$OUT" "backed-up: $HOME/.claude/settings.json" "no settings backup"
}

test_settings_dry_run() {
  setup_home
  run_install --dry-run
  [ ! -e "$HOME/.claude/settings.json" ] || fail "settings written in dry-run"
  assert_contains "$OUT" "DRY-RUN changed: settings.hooks" "dry-run changed"
}

test_settings_jq_missing() {
  setup_home
  local sb="$TEST_HOME/nojq" t
  mkdir -p "$sb"
  for t in bash env dirname basename readlink date mkdir ln mv cp cat rm mktemp stat chmod git; do
    ln -s "$(command -v "$t")" "$sb/$t"
  done
  set +e
  OUT="$(env PATH="$sb" "$REPO_ROOT/install.sh" 2>&1)"
  RC=$?
  set -e
  assert_eq "1" "$RC" "exit code"
  assert_contains "$OUT" "skipped: settings (jq missing)" "skipped"
  assert_symlink_to "$HOME/.claude/CLAUDE.md" "$REPO_ROOT/agents/claude/CLAUDE.md"
}

test_settings_symlink_written_through() {
  setup_home
  mkdir -p "$HOME/.claude" "$HOME/real"
  echo '{"model":"sonnet"}' > "$HOME/real/settings.json"
  chmod 600 "$HOME/real/settings.json"
  ln -s "$HOME/real/settings.json" "$HOME/.claude/settings.json"
  run_install
  assert_symlink_to "$HOME/.claude/settings.json" "$HOME/real/settings.json"
  assert_file_mode "$HOME/real/settings.json" 600
  assert_eq "true" "$(jq '.model == "sonnet" and .permissions.defaultMode == "auto"' "$HOME/real/settings.json")" "target updated"
  assert_eq '{"model":"sonnet"}' "$(cat "$(find "$HOME/.agent-dotfiles-backups" -name settings.json)")" "backup of resolved content"
}

test_settings_dangling_symlink() {
  setup_home
  mkdir -p "$HOME/.claude"
  ln -s "$HOME/nowhere.json" "$HOME/.claude/settings.json"
  run_install
  assert_eq "1" "$RC" "exit code"
  assert_contains "$OUT" "failed: settings (dangling symlink" "failed line"
  assert_symlink_to "$HOME/.claude/settings.json" "$HOME/nowhere.json"
  [ ! -e "$HOME/nowhere.json" ] || fail "target created"
}

test_settings_permission_rules_installed() {
  setup_home
  run_install
  S="$HOME/.claude/settings.json"
  assert_eq "true" "$(jq 'any(.permissions.deny[]; . == "Bash(gh repo delete *)")' "$S")" "deny rule"
  assert_eq "true" "$(jq --slurpfile f "$FRAG" '(.permissions.ask) as $a | $f[0].enforce.permissions.ask | all(. as $e | $a | index($e) != null)' "$S")" "ask rules"
}

test_settings_user_permission_entries_kept() {
  setup_home
  mkdir -p "$HOME/.claude"
  echo '{"permissions":{"deny":["Bash(rm -rf /srv *)"],"ask":["Bash(kubectl delete *)"],"allow":["Bash(ls *)"]}}' > "$HOME/.claude/settings.json"
  run_install
  S="$HOME/.claude/settings.json"
  assert_eq "true" "$(jq '.permissions.deny[0] == "Bash(rm -rf /srv *)" and .permissions.ask[0] == "Bash(kubectl delete *)" and .permissions.allow == ["Bash(ls *)"]' "$S")" "user entries first"
  assert_eq "true" "$(jq --slurpfile f "$FRAG" '(.permissions.deny[1:] == $f[0].enforce.permissions.deny) and (.permissions.ask[1:] == $f[0].enforce.permissions.ask)' "$S")" "fragment entries follow"
}

test_settings_permission_union_no_duplicates() {
  setup_home
  mkdir -p "$HOME/.claude"
  echo '{"permissions":{"ask":["Bash(git push *)"]}}' > "$HOME/.claude/settings.json"
  run_install
  run_install
  assert_eq "1" "$(jq '[.permissions.ask[] | select(. == "Bash(git push *)")] | length' "$HOME/.claude/settings.json")" "single entry"
  assert_not_contains "$OUT" "changed: settings" "second run quiet"
}
