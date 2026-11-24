# Irreversible-Operations Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** User-level guardrails, installed by `install.sh`, that make irreversible or public operations always prompt (`ask`) or always fail (`deny`), whatever the project settings allow.

**Architecture:** Three layers. (1) A PreToolUse hook script `hooks/guard-irreversible.sh` normalises each Bash command and classifies it against the policy. (2) Canonical `permissions.deny`/`ask` rules in `agents/claude/settings.fragment.json`. (3) `install.sh` merges permission lists by union, so the user's own entries survive, and registers the hook.

**Tech Stack:** bash, jq, coreutils. Tests: the repo's own harness (`tests/run.sh`, `tests/lib.sh`, `test_*` functions).

**Spec:** `docs/superpowers/specs/2026-11-24-irreversible-ops-guard-design.md`. The policy (§4), normalisation (§6.2) and test tables (§6.4) are normative. Read them before starting.

## Global Constraints

- No new dependencies: bash, `jq`, coreutils only. The hook makes no network calls and runs no `git`/`gh` commands.
- The hook never outputs `allow`, and never exits 2 on an internal error.
- All code, comments, docs and commit messages in English. No co-author or "Generated with" lines in commits.
- Work on branch `feat/irreversible-ops-guard`. Commit locally, one commit per task. **Never push.**
- Before relying on the PreToolUse output schema, check it against the current Claude Code hooks docs (context7, or `code.claude.com/docs/en/hooks.md`). If it differs from the shape below, follow the docs and report the deviation.
- Full suite must stay green: `bash tests/run.sh`.

## Review Focus

1. Separators inside quotes, e.g. `git commit -m "release; then git push"`. The user expects no prompt. Pinned in Task 1 (`test_guard_quoted_separators_ignored`).
2. Heredoc commit messages that mention a push mid-line (`git commit -F - <<'EOF'` … `Run git push later` … `EOF`). The user expects no prompt. Pinned in Task 1 (`test_guard_heredoc_body_mid_line`).
3. Non-Bash tools whose input contains `git push` (e.g. a `Write` with that text). The user expects no decision. Pinned in Task 1 (`test_guard_ignores_other_tools`).
4. A Bash payload without `tool_input.command` (null or missing). The user expects no decision and no error. Pinned in Task 1 (`test_guard_missing_command`).
5. A long compound command (200 segments). The hook must not slow the session. Pinned in Task 1 (`test_guard_fast_on_long_command`, under 2 seconds).

---

### Task 1: Guard hook script

**Files:**
- Create: `hooks/guard-irreversible.sh` (executable)
- Test: `tests/test_guard_hook.sh`

**Interfaces:**
- Produces: `hooks/guard-irreversible.sh`. It reads the PreToolUse JSON on stdin and always exits 0. On a match it prints exactly one JSON object to stdout:
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"<ask|deny>","permissionDecisionReason":"guard: <text>"}}`.
  On no match it prints nothing. Task 3 registers it by path.

- [ ] **Step 1: Write the failing tests**

In `tests/test_guard_hook.sh`, define a helper `guard_decision <tool_name> <command>`. It builds `{"tool_name":$t,"tool_input":{"command":$c}}` with `jq -n`, pipes it to the script, checks that the exit code is 0, and echoes `.hookSpecificOutput.permissionDecision`, or `none` when stdout is empty. Add a second helper, `assert_decision <expected> <command>`, which uses tool `Bash`.

Tests, one function per policy group. Every command listed in spec §6.4 goes into exactly one of these:
- `test_guard_deny_cases`: the six deny commands from §6.4.
- `test_guard_ask_cases`: the ask commands from §6.4.
- `test_guard_no_decision_cases`: the no-decision commands from §6.4.
- `test_guard_reason_names_policy`: `gh pr merge 12` → reason starts with `guard:` and contains `gh pr merge`.
- `test_guard_deny_beats_ask`: `git push origin feat/x && gh repo delete o/r --yes` → `deny`.
- `test_guard_invalid_json`: stdin `{not json` → exit 0, and the decision is `ask` or `none`, never exit 2.
- `test_guard_quoted_separators_ignored`: `git commit -m "release; then git push"` → `none`, and `git commit -m 'a && gh pr merge 1'` → `none`.
- `test_guard_heredoc_body_mid_line`: a multi-line command `git commit -F - <<'EOF'`, newline, `Run git push later`, newline, `EOF` → `none`.
- `test_guard_ignores_other_tools`: tool `Write` with `{"tool_input":{"content":"git push"}}` → `none`.
- `test_guard_missing_command`: tool `Bash` with `{"tool_input":{}}` → `none`.
- `test_guard_fast_on_long_command`: 200 segments of `git status` joined by ` && ` → `none`, in under 2 seconds (measure with `date +%s%N`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh 2>&1 | grep guard`
Expected: every `test_guard_*` FAILs, because the script does not exist yet.

- [ ] **Step 3: Implement `hooks/guard-irreversible.sh`**

Follow spec §6.2 step by step: split into segments, recurse into `bash -c`/`sh -c`, strip assignments and wrappers, take the basename, skip global options, then classify per §4. Most severe wins (`deny` > `ask`). The force-push-to-main rules and the "no refspec → ask" fallback are in §6.2. The quote-aware split must not treat separators inside `'…'` or `"…"` as boundaries. It must also not classify heredoc body lines as commands: after a `<<WORD` / `<<'WORD'` / `<<-WORD` operator, skip lines up to the terminator. Keep the script under `set -u`, read stdin once, and use `jq` only for the I/O JSON. Do the parsing in bash.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh`
Expected: every test PASSes, including the existing install tests.

- [ ] **Step 5: Commit**

```bash
git add hooks/guard-irreversible.sh tests/test_guard_hook.sh
git commit -m "feat(guard): PreToolUse hook for irreversible operations"
```

---

### Task 2: Policy rules in the fragment and union merge of permission lists

**Files:**
- Modify: `agents/claude/settings.fragment.json` (`enforce.permissions`)
- Modify: `install.sh` (`merge_settings`, the jq merge expression)
- Test: `tests/test_install_settings.sh`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `enforce.permissions.deny` and `enforce.permissions.ask` arrays with exactly the entries in spec §6.1. `merge_settings` union semantics for `permissions.allow|ask|deny`: the local list, then the enforce entries not already in it, keeping order.

- [ ] **Step 1: Write the failing tests**

In `tests/test_install_settings.sh`:
- `test_settings_permission_rules_installed`: fresh home, run install → `.permissions.deny` contains `Bash(gh repo delete *)`, and `.permissions.ask` contains every entry of the fragment's `enforce.permissions.ask`. Compare against `$FRAG` with jq.
- `test_settings_user_permission_entries_kept`: the existing settings has `{"permissions":{"deny":["Bash(rm -rf /srv *)"],"ask":["Bash(kubectl delete *)"],"allow":["Bash(ls *)"]}}`. After install, all three user entries are still present and come first in their lists, and the fragment entries follow.
- `test_settings_permission_union_no_duplicates`: the existing settings already contains `Bash(git push *)` in `ask`. After two installs, `Bash(git push *)` appears exactly once, and the second run's output has no `changed:` lines.
- Update `test_settings_preserves_unknown_keys`: its expectation `.permissions.allow == ["Bash(ls:*)"]` stays valid (the fragment adds no `allow`). Keep it as it is, as a regression check.

- [ ] **Step 2: Add the rules to the fragment, then run the tests**

Add `deny` and `ask` under `enforce.permissions` with the §6.1 entries, verbatim.
Run: `bash tests/run.sh 2>&1 | grep -E 'FAIL|permission'`
Expected: `test_settings_user_permission_entries_kept` FAILs, because the current `$l * enforce` replaces the user's arrays.

- [ ] **Step 3: Implement the union merge in `merge_settings`**

After the existing `($l * ($f.enforce | del(.hooks)))` step, recompute `.permissions[k]` for each `k` in `allow`, `ask`, `deny` that `$f.enforce.permissions` defines, as `(($l.permissions[k] // []) + (($f.enforce.permissions[k] // []) - ($l.permissions[k] // [])))`. Leave `hooks` and the seed logic as they are. The `changed: settings.permissions` reporting comes from the existing loop.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add agents/claude/settings.fragment.json install.sh tests/test_install_settings.sh
git commit -m "feat(settings): user-level deny/ask rules with union merge of permission lists"
```

---

### Task 3: Register the hook, document the guard

**Files:**
- Modify: `agents/claude/settings.fragment.json` (`enforce.hooks.PreToolUse`)
- Modify: `README.md` (new section "Irreversible-operations guard")
- Modify: `docs/verification.md` ("Verify at cutover" list)
- Test: `tests/test_install_settings.sh`

**Interfaces:**
- Consumes: `hooks/guard-irreversible.sh` (Task 1), and the permission rules and union merge (Task 2).
- Produces: a PreToolUse entry `{"matcher":"Bash","hooks":[{"type":"command","command":"~/.agent-dotfiles/hooks/guard-irreversible.sh"}]}`, appended after the existing Serena entries.

- [ ] **Step 1: Write the failing test**

`test_settings_guard_hook_registered_and_runs`: fresh home, run install. Then:
- `.hooks.PreToolUse` contains an entry with matcher `Bash` and the command above;
- `$HOME/.agent-dotfiles/hooks/guard-irreversible.sh` is executable (the anchor link created by the installer makes it reachable);
- running that command through `bash -c` with `HOME` set, fed `{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}`, outputs `permissionDecision` `ask`.

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep guard_hook_registered`
Expected: FAIL (the entry is missing).

- [ ] **Step 3: Add the PreToolUse entry to the fragment**

- [ ] **Step 4: Document**

`README.md`: list what is denied and what asks (link the spec §4). Explain how to run a refused command yourself with `!`. Add the caveat that this guards against agent mistakes, not deliberate evasion, and the union-merge limitation (spec §6.3).
`docs/verification.md`: add these to "Verify at cutover":
- in a project whose `settings.local.json` allows `Bash(gh pr:*)`, `gh pr merge` still prompts;
- `git -C . push` prompts through the hook;
- a subagent's `git push` prompts.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add agents/claude/settings.fragment.json README.md docs/verification.md tests/test_install_settings.sh
git commit -m "feat(guard): register the PreToolUse guard hook; document the guard"
```
