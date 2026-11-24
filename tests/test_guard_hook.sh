# Tests for the irreversible-operations guard hook (hooks/guard-irreversible.sh).

HOOK="$REPO_ROOT/hooks/guard-irreversible.sh"

# guard_decision_in <dir> <mode> <command> -> echoes deny|ask|none (cwd and permission_mode in the input).
guard_decision_in() {
  local out rc=0
  out="$(jq -n --arg d "$1" --arg m "$2" --arg c "$3" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,permission_mode:$m}' | "$HOOK")" || rc=$?
  [ "$rc" -eq 0 ] || { fail "hook exit $rc for: $3"; return 1; }
  if [ -z "$out" ]; then echo none; else jq -r '.hookSpecificOutput.permissionDecision' <<<"$out"; fi
}

# assert_push <dir> <auto-expect> <default-expect> <command>
assert_push() {
  assert_eq "$2" "$(guard_decision_in "$1" auto "$4")" "auto mode: $4"
  assert_eq "$3" "$(guard_decision_in "$1" default "$4")" "default mode: $4"
}

# make_repo <branch>: sets REPO (work tree) with bare remotes origin and upstream,
# main pushed to both, then checks out <branch>. Everything lives under mktemp -d.
make_repo() {
  [ -n "${TEST_HOME:-}" ] || TEST_HOME="$(mktemp -d)" # removed by the runner's teardown
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  local root; root="$(mktemp -d -p "$TEST_HOME")"
  git init -q --bare "$root/origin.git"
  git init -q --bare "$root/upstream.git"
  REPO="$root/work"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name t
  git -C "$REPO" remote add origin "$root/origin.git"
  git -C "$REPO" remote add upstream "$root/upstream.git"
  mkdir -p "$REPO/src" "$REPO/docs"
  echo a > "$REPO/src/App.java"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m init
  git -C "$REPO" push -q origin main
  git -C "$REPO" push -q upstream main
  [ "$1" = main ] || git -C "$REPO" checkout -q -b "$1"
}

# commit_file <path>: add or change a file and commit it in $REPO.
commit_file() {
  mkdir -p "$(dirname "$REPO/$1")"
  echo "$RANDOM" >> "$REPO/$1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "change $1"
}

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
    'gh --repo o/r release delete v1' \
    'gh api --method PATCH repos/o/r' \
    'gh api -XDELETE repos/o/r' \
    'mvn deploy:deploy' \
    'gh secret remove X' \
    'docker image push x'; do
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

test_push_feature_free() {
  make_repo feat/x
  local c
  for c in \
    'git push origin feat/x' \
    'git push' \
    'git push -u origin HEAD' \
    'git push --force origin feat/x' \
    'git push origin --delete feat/x' \
    'git push origin +feat/x:feat/y' \
    'git -C . push' \
    '/usr/bin/git push' \
    'FOO=1 git push' \
    'timeout 30 git push' \
    'nice -n 5 git push' \
    'env FOO=1 git push' \
    "bash -lc 'git push'" \
    'timeout -s KILL 30 git push' \
    'cat <<< "a b"; git push' \
    "$(printf 'cat <<< foo\ngit push')"; do
    assert_push "$REPO" none none "$c"
  done
}

test_push_protected_by_mode() {
  make_repo feat/x
  assert_push "$REPO" none ask 'git push origin main'
  assert_push "$REPO" none ask 'git push upstream feat/x'
  assert_push "$REPO" none ask 'git push --tags'
  assert_push "$REPO" none ask 'git push --all'
  assert_push "$REPO" none ask 'git push --mirror origin'
  assert_push "$REPO" none ask 'git --git-dir=/x push'
  assert_push "$REPO" none ask 'git push origin "$BRANCH"'
  assert_push "$REPO" none ask 'git push origin refs/heads/*:refs/heads/*'
  git -C "$REPO" checkout -q main
  assert_push "$REPO" none ask 'git push'
  git -C "$REPO" checkout -q --detach
  assert_push "$REPO" none ask 'git push'
}

test_push_deny_main() {
  make_repo feat/x
  local c
  for c in 'git push -f origin main' 'git push origin --delete main' 'git push origin :master' \
           'git push --force origin HEAD:main' 'git push origin +main'; do
    assert_push "$REPO" deny deny "$c"
  done
  git -C "$REPO" checkout -q main
  assert_push "$REPO" deny deny 'git push --force'
}

test_push_docs_only() {
  make_repo main
  commit_file CHANGELOG.md
  assert_push "$REPO" none none 'git push origin main'
  assert_push "$REPO" none none 'git push'
  assert_push "$REPO" deny deny 'git push -f origin main'
  assert_push "$REPO" none ask 'git push upstream main'
  commit_file src/App.java
  assert_push "$REPO" none ask 'git push origin main'

  make_repo main
  commit_file docs/HANDOFF-x.md
  assert_push "$REPO" none none 'git push origin main'
  commit_file docs/HANDOFF/sub/y.md
  assert_push "$REPO" none ask 'git push origin main'

  make_repo main
  commit_file README.md
  git -C "$REPO" update-ref -d refs/remotes/origin/main
  assert_push "$REPO" none ask 'git push origin main'
}

test_push_docs_only_rename_hides_nothing() {
  make_repo main
  git -C "$REPO" mv src/App.java CHANGELOG.md
  git -C "$REPO" commit -q -m rename
  assert_push "$REPO" none ask 'git push origin main'
}

test_push_from_subdirectory() {
  make_repo feat/x
  mkdir -p "$REPO/sub/dir"
  assert_push "$REPO/sub/dir" none none 'git push'
  git -C "$REPO" checkout -q main
  assert_push "$REPO/sub/dir" none ask 'git push'
}

test_push_outside_repo() {
  make_repo feat/x
  local plain="$TEST_HOME/plain"; mkdir -p "$plain"
  assert_push "$plain" none ask 'git push'
  assert_push "$plain" none none 'git push origin feat/x'
  assert_push "$plain" none none "git -C $REPO push"
}

test_push_head_to_main() {
  make_repo feat/x
  assert_push "$REPO" none ask 'git push origin HEAD:main'
  assert_push "$REPO" none ask 'git push origin HEAD:refs/heads/master'
  git -C "$REPO" checkout -q main
  assert_push "$REPO" none ask 'git push origin HEAD'
}

test_push_tracking_upstream_remote() {
  make_repo feat/x
  git -C "$REPO" config branch.feat/x.remote upstream
  assert_push "$REPO" none ask 'git push'
  git -C "$REPO" config branch.feat/x.remote origin
  assert_push "$REPO" none none 'git push'
}

test_push_oversized_by_mode() {
  local pad cmd
  pad="$(head -c 50000 /dev/zero | tr '\0' 'a')"
  cmd="echo $pad && git push origin feat/x"
  assert_eq none "$(guard_decision_in /tmp auto "$cmd")" "oversized push, auto"
  assert_eq ask "$(guard_decision_in /tmp default "$cmd")" "oversized push, default"
  assert_eq ask "$(guard_decision_in /tmp auto "echo $pad && git push -f origin main")" "oversized force main, auto"
}

test_push_follows_cd() {
  make_repo feat/x; local feat=$REPO
  make_repo main; local mainr=$REPO
  # cwd is the feature repo; the shell moves into the main repo first
  assert_push "$feat" none ask "cd $mainr && git push"
  assert_push "$feat" none ask "pushd $mainr && git push"
  assert_push "$feat" none ask "(cd $mainr && git push)"
  assert_push "$feat" none ask "cd $mainr; git push"
  assert_push "$feat" none ask 'cd x && git push'
  assert_push "$feat" none ask 'cd "$X" && git push'
  assert_push "$feat" none ask 'cd && git push'
  assert_push "$feat" none ask 'cd - && git push'
  assert_push "$feat" none ask "cd $mainr && popd && git push"
  assert_push "$feat" none ask "bash -c 'cd $mainr && git push'"
  # cwd is the main repo; moving into the feature repo makes the push free
  assert_push "$mainr" none none "cd $feat && git push"
  assert_push "$mainr" none none "cd $feat && git -C . push"
  # a cd that does not apply to the push must not leak
  assert_push "$mainr" none ask "(cd $feat); git push"
  assert_push "$mainr" none ask "cd $feat | cat; git push"
  assert_push "$mainr" none ask "cd $feat & git push"
  assert_push "$mainr" none ask "bash -c 'cd $feat'; git push"
  # relative cd and -C after cd resolve against the tracked directory
  assert_push /nonexistent none none "cd $(dirname "$feat") && cd work && git push"
  assert_push /nonexistent none ask "cd $(dirname "$mainr") && git -C work push"
}

test_push_cd_docs_only_uses_target_repo() {
  make_repo main; local docs=$REPO
  commit_file CHANGELOG.md
  make_repo main; local code=$REPO
  commit_file src/App.java
  # the docs-only range of the cwd repo must not excuse the target repo
  assert_push "$docs" none none 'git push origin main'
  assert_push "$docs" none ask "cd $code && git push origin main"
  assert_push "$code" none none "cd $docs && git push origin main"
}

test_push_env_options() {
  make_repo feat/x; local feat=$REPO
  make_repo main; local mainr=$REPO
  assert_push "$feat" none ask "env -C $mainr git push"
  assert_push "$feat" none ask "env --chdir=$mainr git push origin main"
  assert_push "$feat" none ask "env --chdir $mainr git push"
  assert_push "$feat" none ask 'env -C "$X" git push'
  assert_push "$feat" deny deny 'env -C /x git push --force origin main'
  assert_push "$feat" deny deny 'env -u FOO git push --force origin main'
  assert_push "$feat" deny deny 'env --unset=FOO -i git push -f origin main'
  assert_push "$feat" none ask "env -S 'git -C $mainr push'"
  assert_push "$feat" none none 'env -u FOO -i git push'
  assert_push "$feat" none ask 'env --some-new-flag git push'
  assert_push "$feat" none ask 'env -a foo git push'
  assert_push "$mainr" none none "env -C $feat git push"
  assert_push "$mainr" none none "env -C $feat FOO=1 git push"
}

test_guard_env_split_string_ask() {
  assert_decision ask "env -S 'gh pr merge 1'"
  assert_decision ask "env --split-string='gh pr merge 1'"
}
