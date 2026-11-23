# Tests for MCP registration (Task 5).

C7_ADD="mcp add --scope user --transport http context7 https://mcp.context7.com/mcp -H CONTEXT7_API_KEY: dummy"
SERENA_ADD="mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd"

write_claude_json() { # $1 = serena args JSON, $2 = context7 header value
  cat > "$HOME/.claude.json" <<JSON
{"mcpServers":{
 "context7":{"type":"http","url":"https://mcp.context7.com/mcp","headers":{"CONTEXT7_API_KEY":"$2"}},
 "serena":{"type":"stdio","command":"serena","args":$1,"env":{}}}}
JSON
}

test_mcp_added_when_absent() {
  setup_home
  run_install
  assert_eq 0 "$RC" "exit"
  assert_contains "$(cat "$TEST_HOME/claude.log")" "$C7_ADD" "context7 add"
  assert_contains "$(cat "$TEST_HOME/claude.log")" "$SERENA_ADD" "serena add"
  assert_contains "$OUT" "mcp-added: context7" "context7 line"
  assert_contains "$OUT" "mcp-added: serena" "serena line"
  assert_not_contains "$OUT" "dummy" "secret not printed"
}

test_mcp_ok_when_equal() {
  setup_home
  write_claude_json '["start-mcp-server","--context","claude-code","--project-from-cwd"]' x
  run_install
  assert_eq 0 "$RC" "exit"
  assert_contains "$OUT" "mcp-ok: context7" "context7"
  assert_contains "$OUT" "mcp-ok: serena" "serena"
  assert_not_contains "$(cat "$TEST_HOME/claude.log" 2>/dev/null || true)" "mcp add" "no add"
}

test_mcp_drift_reported() {
  setup_home
  write_claude_json '["start-mcp-server","--project-from-cwd"]' x
  run_install
  assert_eq 0 "$RC" "exit"
  assert_contains "$OUT" "drift: mcp serena (args)" "drift"
  assert_contains "$OUT" "mcp-ok: context7" "context7 ok"
  assert_not_contains "$(cat "$TEST_HOME/claude.log" 2>/dev/null || true)" "mcp add" "no add"
}

test_mcp_drift_header_name_and_url() {
  setup_home
  cat > "$HOME/.claude.json" <<'JSON'
{"mcpServers":{"context7":{"type":"http","url":"https://other.example/mcp","headers":{"X_OTHER":"v"}}}}
JSON
  run_install
  assert_contains "$OUT" "drift: mcp context7 (url,headers)" "drift fields"
  assert_not_contains "$OUT" "X_OTHER" "live header names not printed"
  assert_not_contains "$(cat "$TEST_HOME/claude.log")" "mcp add --scope user --transport http" "context7 untouched"
}

test_mcp_secret_missing() {
  setup_home
  NO_CONTEXT7_KEY=1 run_install
  assert_eq 1 "$RC" "exit"
  assert_contains "$OUT" "skipped: mcp context7 (env CONTEXT7_API_KEY unset)" "skipped"
  assert_contains "$OUT" "mcp-added: serena" "serena still added"
  assert_not_contains "$(cat "$TEST_HOME/claude.log")" "context7" "context7 not added"
}

test_mcp_never_prints_secrets() {
  setup_home
  write_claude_json '["start-mcp-server","--context","claude-code","--project-from-cwd"]' SECRET123
  run_install
  assert_not_contains "$OUT" "SECRET123" "secret leaked"
  write_claude_json '["start-mcp-server"]' SECRET123
  run_install
  assert_not_contains "$OUT" "SECRET123" "secret leaked on drift"
}

test_mcp_dry_run() {
  setup_home
  run_install --dry-run
  assert_eq 0 "$RC" "exit"
  assert_contains "$OUT" "DRY-RUN mcp-added: context7" "context7"
  assert_contains "$OUT" "DRY-RUN mcp-added: serena" "serena"
  [ ! -s "$TEST_HOME/claude.log" ] || fail "claude was called in dry-run"
}

test_mcp_add_failure() {
  setup_home
  cat > "$TEST_HOME/bin/claude" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = mcp ] && exit 7
exit 0
STUB
  run_install
  assert_eq 1 "$RC" "exit"
  assert_contains "$OUT" "failed: mcp serena (claude mcp add exit 7)" "failed line"
  assert_not_contains "$OUT" "mcp-added: serena" "no added line"
}

test_mcp_invalid_manifest_fails() {
  setup_home
  local copy="$TEST_HOME/repocopy"
  mkdir "$copy"
  (cd "$REPO_ROOT" && tar --exclude=.git -cf - .) | tar -xf - -C "$copy"
  head -c 20 "$REPO_ROOT/mcp/servers.json" > "$copy/mcp/servers.json"
  set +e
  OUT="$(env PATH="$TEST_HOME/bin:$PATH" CONTEXT7_API_KEY=dummy "$copy/install.sh" 2>&1)"
  RC=$?
  set -e
  assert_eq 1 "$RC" "exit"
  assert_contains "$OUT" "failed: mcp (invalid manifest)" "line"
}
