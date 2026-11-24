# Push Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feature-branch pushes and docs-only pushes to `main` run freely. Other pushes to `main`/`master` or to `upstream` run only on explicit user request (auto-mode classifier), or ask outside auto mode.

**Architecture:** The guard hook resolves push destinations (with read-only local git calls) and decides `deny` / `ask` / no decision per spec §5.1. The settings fragment drops the `git push` ask rule and adds `enforce.autoMode` (`classifyAllShell`, one `soft_deny` entry). The installer merges `autoMode` lists by union.

**Tech Stack:** bash, jq, git, coreutils. Tests: `tests/run.sh` harness.

**Spec:** `docs/superpowers/specs/2026-11-24-push-policy-design.md` (amends `2026-11-24-irreversible-ops-guard-design.md`). §5 is normative: the decision table in §5.1, the exact soft-deny text in §5.3, and the test cases in §5.5.

## Global Constraints

- Dependencies: bash, jq, git, coreutils only. The hook's git calls are local and read-only (`rev-parse`, `config`, `log`). It makes no network calls (no `fetch`, no `ls-remote`).
- The hook never outputs `allow` and never exits 2. Any error in push resolution makes the push "protected", never "free".
- English everywhere. No co-author or "Generated with" lines in commits.
- Branch `feat/push-policy`. Commit locally, one commit per task. Never push.
- Verify against the current Claude Code docs that PreToolUse input carries `permission_mode` and `cwd`, and what values `permission_mode` takes. Use context7, or `code.claude.com/docs/en/hooks.md`. If a field is missing, report BLOCKED rather than guessing.
- Full suite green: `bash tests/run.sh`.

## Review Focus

1. A push from inside a subdirectory of the repo (`cwd` is not the repo root). The current branch and the docs-only check must still work. Pinned in Task 1 (`test_push_from_subdirectory`).
2. `cwd` that is not a git repo (e.g. `/tmp`), with a bare `git push`. The push is protected: `ask` in default mode, no decision in auto mode, and never an error. Pinned in Task 1 (`test_push_outside_repo`).
3. A refspec whose source is `HEAD` while on a feature branch, with destination `main` (`git push origin HEAD:main`). This is a push to `main`. Pinned in Task 1 (`test_push_head_to_main`).
4. A branch whose upstream remote is `upstream` (`branch.<b>.remote=upstream`), with a bare `git push`. It is protected. Pinned in Task 1 (`test_push_tracking_upstream_remote`).
5. Upgrading an existing install. The user's settings still hold the old `Bash(git push *)` ask entry and the stale `autoMode` block. The installer must keep the user's `autoMode.soft_deny` entries and add the new entry once. Pinned in Task 2 (`test_settings_automode_union`). The manual removals are cutover steps (spec §5.2, §5.4).

---

### Task 1: Push classification in the guard hook

**Files:**
- Modify: `hooks/guard-irreversible.sh` (`git push` handling)
- Test: `tests/test_guard_hook.sh`

**Interfaces:**
- Consumes: the existing hook I/O contract. On stdin it gets `{"tool_name","tool_input":{"command"},"cwd","permission_mode"}`. On stdout it emits a decision JSON, or nothing.
- Produces: push decisions per spec §5.1. Task 2 relies on the hook giving no decision for any protected push when `permission_mode` is `auto`.

- [ ] **Step 1: Update and add the tests**

The existing push rows in the ask and deny groups change meaning. Move them according to spec §5.1:
- `git push`, `git push origin feat/x`, `git -C . push`, `/usr/bin/git push`, `FOO=1 git push`, `timeout 30 git push`, `cd x && git push`, and the other plain-push variants are classified by destination. Rewrite each as an explicit case, with a temporary repo where the case depends on the current branch.
- Extend the helper to `guard_decision_in <dir> <mode> <command>`. It adds `cwd` and `permission_mode` to the input JSON.
- Add a fixture helper `make_repo <branch>`. It creates a temp repo with a bare remote named `origin` (and `upstream` where needed), commits a file, and pushes `main` so that `origin/main` exists. It then checks out `<branch>`.
- Tests, one function per spec §5.5 group:
  - `test_push_feature_free`
  - `test_push_protected_by_mode` (assert both modes for each case)
  - `test_push_deny_main`
  - `test_push_docs_only` (all six §5.5 docs-only cases)
- Add the Review Focus tests:
  - `test_push_from_subdirectory`
  - `test_push_outside_repo`
  - `test_push_head_to_main`
  - `test_push_tracking_upstream_remote`
- Keep all non-push rows unchanged.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh 2>&1 | grep -E 'test_push|FAIL'`
Expected: the new push tests FAIL. The non-push tests still PASS.

- [ ] **Step 3: Implement**

Follow spec §5.1 in this order: resolve the remote, resolve the destinations, resolve the current branch, run the docs-only check, then decide.
- For git calls, use `git -C <dir>`. `<dir>` is the push's `-C` value resolved against `cwd`, or else `cwd`.
- Keep the 8 KB oversized fallback. Above the cap, any `git push` mention gives `ask` outside auto mode and no decision in auto mode, except that a visible force push to `main` still gives `ask` (as today). Record this choice in the report.
- Update the README sentence about the hook's git calls only if Task 2 does not cover it. It does, so leave the README alone.

- [ ] **Step 4: Run the full suite**

Run: `bash tests/run.sh`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/guard-irreversible.sh tests/test_guard_hook.sh
git commit -m "feat(guard): destination-aware push policy (feature branches and docs-only pushes free)"
```

---

### Task 2: Settings, auto mode and docs

**Files:**
- Modify: `agents/claude/settings.fragment.json`
- Modify: `install.sh` (`merge_settings`)
- Modify: `README.md` (guard section)
- Modify: `docs/verification.md` (cutover checks)
- Test: `tests/test_install_settings.sh`

**Interfaces:**
- Consumes: Task 1's behaviour. In auto mode the hook gives no decision for protected pushes, so the classifier rules.
- Produces:
  - `enforce.permissions.ask` without `Bash(git push *)`.
  - `enforce.autoMode = {"classifyAllShell": true, "soft_deny": ["$defaults", "<exact §5.3 text>"]}`.
  - Union merge for `autoMode.soft_deny|allow|hard_deny|environment` when the fragment defines them. `classifyAllShell` is enforced.

- [ ] **Step 1: Write the failing tests**

- `test_settings_no_git_push_ask`: after a fresh install, `.permissions.ask` does not contain `Bash(git push *)`.
- `test_settings_automode_enforced`: after a fresh install, `.autoMode.classifyAllShell == true` and `.autoMode.soft_deny` equals the fragment's list.
- `test_settings_automode_union`: the existing settings hold `{"autoMode":{"environment":["x"],"soft_deny":["$defaults","user entry"]}}`. After two installs:
  - `environment` is `["x"]`;
  - `soft_deny` is `["$defaults","user entry","<§5.3 text>"]`, with `$defaults` exactly once and the §5.3 text exactly once;
  - the second run has no `changed:` lines.
- Update any existing test that expects `Bash(git push *)` in the installed `ask` list.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh 2>&1 | grep -E 'automode|git_push_ask|FAIL'`
Expected: the new tests FAIL.

- [ ] **Step 3: Implement**

- Fragment: remove the `Bash(git push *)` entry. Add `enforce.autoMode` with the exact §5.3 soft-deny text.
- `merge_settings`: apply the same union expression used for the permission lists to the `autoMode` list keys that the fragment defines.

- [ ] **Step 4: Document**

- README guard section, in plain words:
  - Feature-branch pushes and docs-only pushes to `main` are free.
  - Other pushes to `main`/`master` or `upstream` need the user's explicit request in auto mode, and a prompt in other modes.
  - Force push and deletion of `main`/`master` are denied.
  - The effect of `classifyAllShell`: project allow lists no longer skip the classifier in auto mode.
  - The two manual upgrade steps (spec §5.2, §5.4).
- `docs/verification.md`: add the four push checks from spec §5.6 to "Verify at cutover", plus a docs-only push to `main`.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add agents/claude/settings.fragment.json install.sh README.md docs/verification.md tests/test_install_settings.sh
git commit -m "feat(settings): auto-mode push rule, classifyAllShell, union merge of autoMode lists"
```
