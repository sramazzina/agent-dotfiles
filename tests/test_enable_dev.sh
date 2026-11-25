# Tests for install.sh --enable-dev (Task 6).

IMPORT='@~/.claude/profiles/dev.md'

mkrepo() { mkdir -p "$1" && git init -q "$1"; }

test_enable_dev_creates_file() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  run_install --enable-dev "$TEST_HOME/proj"
  assert_eq "0" "$RC" "rc"
  assert_eq "$IMPORT" "$(cat "$TEST_HOME/proj/CLAUDE.local.md")" "content"
  assert_eq "1" "$(wc -l < "$TEST_HOME/proj/CLAUDE.local.md")" "one line with newline"
  grep -qxF 'CLAUDE.local.md' "$TEST_HOME/proj/.git/info/exclude" || fail "exclude entry"
  assert_eq "" "$(git -C "$TEST_HOME/proj" status --porcelain)" "git status"
  assert_contains "$OUT" "created:" "created"
  assert_contains "$OUT" "First session in this project will ask to approve the external import — accept it." "reminder"
}

test_enable_dev_appends_without_trailing_newline() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  printf 'local notes' > "$TEST_HOME/proj/CLAUDE.local.md"
  run_install --enable-dev "$TEST_HOME/proj"
  assert_eq "local notes" "$(sed -n 1p "$TEST_HOME/proj/CLAUDE.local.md")" "line 1"
  assert_eq "$IMPORT" "$(sed -n 2p "$TEST_HOME/proj/CLAUDE.local.md")" "line 2"
  assert_contains "$OUT" "appended:" "appended"
}

test_enable_dev_idempotent() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  run_install --enable-dev "$TEST_HOME/proj"
  run_install --enable-dev "$TEST_HOME/proj"
  assert_eq "1" "$(grep -cxF "$IMPORT" "$TEST_HOME/proj/CLAUDE.local.md")" "import lines"
  assert_eq "1" "$(grep -cxF 'CLAUDE.local.md' "$TEST_HOME/proj/.git/info/exclude")" "exclude entries"
  assert_contains "$OUT" "unchanged:" "unchanged"
  assert_not_contains "$OUT" "created:" "no created"
  assert_not_contains "$OUT" "appended:" "no appended"
}

test_enable_dev_respects_existing_ignore() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  echo 'CLAUDE.local.md' > "$TEST_HOME/proj/.gitignore"
  local before; before="$(cat "$TEST_HOME/proj/.git/info/exclude")"
  run_install --enable-dev "$TEST_HOME/proj"
  assert_eq "$before" "$(cat "$TEST_HOME/proj/.git/info/exclude")" "exclude unchanged"
}

test_enable_dev_not_git() {
  setup_home
  mkdir "$TEST_HOME/plain"
  run_install --enable-dev "$TEST_HOME/plain"
  assert_eq "0" "$RC" "rc"
  [ -f "$TEST_HOME/plain/CLAUDE.local.md" ] || fail "file created"
  assert_contains "$OUT" "skipped: ignore (not a git repo)" "skip"
}

test_enable_dev_path_with_spaces() {
  setup_home
  mkrepo "$TEST_HOME/my project"
  run_install --enable-dev "$TEST_HOME/my project"
  assert_eq "0" "$RC" "rc"
  assert_eq "$IMPORT" "$(cat "$TEST_HOME/my project/CLAUDE.local.md")" "content"
  grep -qxF 'CLAUDE.local.md' "$TEST_HOME/my project/.git/info/exclude" || fail "exclude entry"
}

test_enable_dev_missing_dir() {
  setup_home
  run_install --enable-dev "$TEST_HOME/nope"
  assert_eq "2" "$RC" "rc"
}

test_enable_dev_dry_run() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  local before; before="$(cat "$TEST_HOME/proj/.git/info/exclude")"
  run_install --enable-dev "$TEST_HOME/proj" --dry-run
  assert_eq "0" "$RC" "rc"
  [ ! -e "$TEST_HOME/proj/CLAUDE.local.md" ] || fail "file created in dry-run"
  assert_eq "$before" "$(cat "$TEST_HOME/proj/.git/info/exclude")" "exclude untouched"
  assert_contains "$OUT" "DRY-RUN created:" "dry created"
  assert_contains "$OUT" "First session in this project" "reminder"
}

test_enable_dev_no_full_install() {
  setup_home
  mkdir "$TEST_HOME/plain"
  run_install --enable-dev "$TEST_HOME/plain"
  [ ! -e "$HOME/.claude/CLAUDE.md" ] || fail "full install ran"
  assert_contains "$OUT" "skipped: dev-profile-check (run install.sh first)" "profile warn"
  assert_eq "0" "$RC" "warning is not failure"
}

test_enable_dev_empty_arg_is_usage_error() {
  setup_home
  run_install --enable-dev ""
  assert_eq "2" "$RC" "rc"
  [ ! -e "$HOME/.claude/CLAUDE.md" ] || fail "full install ran"
}

test_enable_dev_crlf_import_detected() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  printf '%s\r\n' "$IMPORT" > "$TEST_HOME/proj/CLAUDE.local.md"
  run_install --enable-dev "$TEST_HOME/proj"
  assert_contains "$OUT" "unchanged: $TEST_HOME/proj/CLAUDE.local.md" "unchanged"
  assert_eq "1" "$(tr -d '\r' < "$TEST_HOME/proj/CLAUDE.local.md" | grep -cxF "$IMPORT")" "import lines"
}

LANG_JAVA='@~/.agent-dotfiles/languages/java.md'

test_enable_dev_lang_creates_both_lines() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  run_install --enable-dev "$TEST_HOME/proj" --lang java
  assert_eq "0" "$RC" "rc"
  assert_eq "2" "$(wc -l < "$TEST_HOME/proj/CLAUDE.local.md")" "two lines"
  assert_eq "$IMPORT" "$(sed -n 1p "$TEST_HOME/proj/CLAUDE.local.md")" "line 1"
  assert_eq "$LANG_JAVA" "$(sed -n 2p "$TEST_HOME/proj/CLAUDE.local.md")" "line 2"
}

test_enable_dev_lang_on_already_enabled_project() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  printf '%s\n' "$IMPORT" > "$TEST_HOME/proj/CLAUDE.local.md"
  run_install --enable-dev "$TEST_HOME/proj" --lang java
  assert_eq "$IMPORT" "$(sed -n 1p "$TEST_HOME/proj/CLAUDE.local.md")" "line 1"
  assert_eq "$LANG_JAVA" "$(sed -n 2p "$TEST_HOME/proj/CLAUDE.local.md")" "line 2"
  assert_eq "2" "$(wc -l < "$TEST_HOME/proj/CLAUDE.local.md")" "two lines"
  assert_contains "$OUT" "unchanged:" "unchanged"
  assert_contains "$OUT" "appended:" "appended"
}

test_enable_dev_lang_idempotent() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  run_install --enable-dev "$TEST_HOME/proj" --lang java
  run_install --enable-dev "$TEST_HOME/proj" --lang java
  assert_eq "2" "$(wc -l < "$TEST_HOME/proj/CLAUDE.local.md")" "two lines"
  assert_not_contains "$OUT" "appended:" "no appended"
  assert_not_contains "$OUT" "created:" "no created"
}

test_enable_dev_lang_repeated_same() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  run_install --enable-dev "$TEST_HOME/proj" --lang java --lang java
  assert_eq "1" "$(grep -cxF "$LANG_JAVA" "$TEST_HOME/proj/CLAUDE.local.md")" "java lines"
}

test_enable_dev_lang_unknown_writes_nothing() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  run_install --enable-dev "$TEST_HOME/proj" --lang java --lang cobol
  assert_eq "2" "$RC" "rc"
  [ ! -e "$TEST_HOME/proj/CLAUDE.local.md" ] || fail "CLAUDE.local.md written"
  ! grep -qxF 'CLAUDE.local.md' "$TEST_HOME/proj/.git/info/exclude" || fail "exclude written"
  assert_contains "$OUT" "unknown language: cobol" "unknown"
  assert_contains "$OUT" "available: java" "available"
}

test_lang_without_enable_dev_is_usage_error() {
  setup_home
  run_install --lang java
  assert_eq "2" "$RC" "rc"
  assert_contains "$OUT" "Usage:" "usage"
  [ ! -e "$HOME/.claude/CLAUDE.md" ] && [ ! -L "$HOME/.claude/CLAUDE.md" ] || fail "install ran"
}

test_enable_dev_lang_missing_value() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  run_install --enable-dev "$TEST_HOME/proj" --lang
  assert_eq "2" "$RC" "rc"
}

test_enable_dev_lang_dry_run() {
  setup_home
  mkrepo "$TEST_HOME/proj"
  run_install --dry-run --enable-dev "$TEST_HOME/proj" --lang java
  [ ! -e "$TEST_HOME/proj/CLAUDE.local.md" ] || fail "file written in dry run"
  assert_contains "$OUT" "DRY-RUN created:" "dry-run created"
}
