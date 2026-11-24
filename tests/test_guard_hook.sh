# Tests for the irreversible-operations guard hook (hooks/guard-irreversible.sh).

HOOK="$REPO_ROOT/hooks/guard-irreversible.sh"

# guard_decision <tool_name> <command> -> echoes deny|ask|none; fails on non-zero exit.
guard_decision() {
  local out rc=0
  out="$(jq -n --arg t "$1" --arg c "$2" '{tool_name:$t,tool_input:{command:$c}}' | "$HOOK")" || rc=$?
  [ "$rc" -eq 0 ] || { fail "hook exit $rc for: $2"; return 1; }
  if [ -z "$out" ]; then echo none; else jq -r '.hookSpecificOutput.permissionDecision' <<<"$out"; fi
}

assert_decision() {
  local got
  got="$(guard_decision Bash "$2")"
  assert_eq "$1" "$got" "decision for: $2"
}

test_guard_deny_cases() {
  local c
  for c in \
    'gh repo delete x/y --yes' \
    'git push --force origin main' \
    'git push -f origin HEAD:main' \
    'git push -fu origin main' \
    'git push origin HEAD:refs/heads/master --force-with-lease=main:abc' \
    'git push origin +main' \
    'git -C /tmp/r push --force-with-lease origin master' \
    'bash -c "git push -f origin main"'; do
    assert_decision deny "$c"
  done
}

test_guard_ask_cases() {
  local c
  for c in \
    'git push' \
    'git push origin feat/x' \
    'git push --force origin feat/x' \
    'git push --force' \
    'git push origin --delete feat/x' \
    'git -C . push' \
    '/usr/bin/git push' \
    'FOO=1 git push' \
    'timeout 30 git push' \
    'cd x && git push' \
    'gh pr merge 12 --squash' \
    'gh -R o/r pr merge 12' \
    'gh release create v1.0.0' \
    'mvn -B deploy' \
    './mvnw clean deploy -DskipTests' \
    'docker push ghcr.io/x/y:1' \
    'gh workflow run ci.yml' \
    'gh secret set TOKEN' \
    'gh api -X DELETE repos/o/r/git/refs/heads/x' \
    'gh api repos/o/r/pulls/1/merge -f merge_method=squash' \
    "sh -c 'gh pr merge 1'" \
    'git --git-dir=/x push' \
    'nice -n 5 git push' \
    'env FOO=1 git push' \
    'gh --repo o/r release delete v1' \
    'gh api --method PATCH repos/o/r' \
    'gh api -XDELETE repos/o/r' \
    'mvn deploy:deploy' \
    'gh secret remove X' \
    "bash -lc 'git push'" \
    'timeout -s KILL 30 git push' \
    'cat <<< "a b"; git push' \
    "$(printf 'cat <<< foo\ngit push')"; do
    assert_decision ask "$c"
  done
}

test_guard_no_decision_cases() {
  local c
  for c in \
    'git status' \
    'git log --oneline' \
    'git commit -m "fix push retry"' \
    'echo "git push"' \
    'gh pr view 12' \
    'gh pr create --fill' \
    'gh api repos/o/r/pulls' \
    'gh release view v1' \
    'mvn -B verify' \
    'docker pull x' \
    'gh secret list' \
    'git tag v1.0.0' \
    'gh api --method GET repos/o/r'; do
    assert_decision none "$c"
  done
}

test_guard_reason_names_policy() {
  local out reason
  out="$(jq -n --arg c 'gh pr merge 12' '{tool_name:"Bash",tool_input:{command:$c}}' | "$HOOK")"
  reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$out")"
  assert_eq "PreToolUse" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out")" "event name"
  case "$reason" in guard:*) ;; *) fail "reason does not start with 'guard:': $reason";; esac
  assert_contains "$reason" "gh pr merge" "reason"
}

test_guard_deny_beats_ask() {
  assert_decision deny 'git push origin feat/x && gh repo delete o/r --yes'
}

test_guard_invalid_json() {
  local out rc=0 d
  out="$(printf '%s' '{not json' | "$HOOK" 2>/dev/null)" || rc=$?
  assert_eq 0 "$rc" "exit code on invalid JSON"
  if [ -z "$out" ]; then d=none; else d="$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")"; fi
  case "$d" in ask|none) ;; *) fail "unexpected decision on invalid JSON: $d";; esac
}

test_guard_quoted_separators_ignored() {
  assert_decision none 'git commit -m "release; then git push"'
  assert_decision none "git commit -m 'a && gh pr merge 1'"
}

test_guard_heredoc_body_mid_line() {
  assert_decision none "$(printf "git commit -F - <<'EOF'\nRun git push later\nEOF")"
}

test_guard_ignores_other_tools() {
  local out rc=0
  out="$(printf '%s' '{"tool_name":"Write","tool_input":{"content":"git push"}}' | "$HOOK")" || rc=$?
  assert_eq 0 "$rc" "exit code"
  assert_eq "" "$out" "output for Write tool"
}

test_guard_missing_command() {
  local out rc=0
  out="$(printf '%s' '{"tool_name":"Bash","tool_input":{}}' | "$HOOK")" || rc=$?
  assert_eq 0 "$rc" "exit code"
  assert_eq "" "$out" "output without command"
}

test_guard_fast_on_long_command() {
  local cmd="git status" i t0 t1 ms
  for i in $(seq 2 200); do cmd+=" && git status"; done
  t0="$(date +%s%N)"
  assert_decision none "$cmd"
  t1="$(date +%s%N)"
  ms=$(( (t1 - t0) / 1000000 ))
  [ "$ms" -lt 2000 ] || fail "200-segment command took ${ms}ms"
}

test_guard_oversized_command_fallback() {
  local pad harmful t0 t1 ms
  pad="$(head -c 50000 /dev/zero | tr '\0' 'a')"
  t0="$(date +%s%N)"
  assert_decision none "echo $pad"
  assert_decision ask "echo $pad && git push"
  assert_decision none "$(printf 'cat <<EOF\n%s\nEOF' "$pad")"
  t1="$(date +%s%N)"
  ms=$(( (t1 - t0) / 1000000 ))
  [ "$ms" -lt 3000 ] || fail "oversized commands took ${ms}ms"
}
