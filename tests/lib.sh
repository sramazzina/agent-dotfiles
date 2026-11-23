# Shared test helpers. Sourced by tests/run.sh; no third-party framework.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "  ASSERT: $*" >&2; return 1; }

setup_home() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME" TEST_HOME
  echo '{}' > "$HOME/.claude.json"
  mkdir -p "$TEST_HOME/bin"
  cat > "$TEST_HOME/bin/claude" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$TEST_HOME/claude.log"
exit 0
STUB
  chmod +x "$TEST_HOME/bin/claude"
}

teardown_home() {
  if [ -n "${TEST_HOME:-}" ]; then chmod -R u+w "$TEST_HOME" 2>/dev/null || true; rm -rf "$TEST_HOME"; fi
  return 0
}

run_install() {
  local env_key=(CONTEXT7_API_KEY=dummy)
  [ "${NO_CONTEXT7_KEY:-}" = 1 ] && env_key=()
  set +e
  OUT="$(env PATH="$TEST_HOME/bin:$PATH" "${env_key[@]}" "$REPO_ROOT/install.sh" "$@" 2>&1)"
  RC=$?
  set -e
  return 0
}

assert_eq() { [ "$1" = "$2" ] || fail "$3: expected '$1', got '$2'"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "$3: missing '$2'";; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "$3: unexpected '$2'";; esac; }
assert_symlink_to() {
  [ -L "$1" ] || { fail "$1 is not a symlink"; return 1; }
  assert_eq "$2" "$(readlink "$1")" "symlink target of $1"
}
assert_file_mode() { assert_eq "$2" "$(stat -c %a "$1")" "mode of $1"; }
