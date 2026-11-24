# Irreversible-operations guard — Design

Date: 2026-11-24 · Status: approved by the user (2026-11-24)
Origin: issue #14 (server migration). Auditing cardine, hop-opentelemetry-plugin and data-loader-v2 showed project `.claude/settings.local.json` files with broad allow rules that bypass the user's own rules.

## 1. Intent

Coding agents must not perform irreversible or public operations (merge a PR, push, publish a release or an artifact, delete a repository) without the user confirming each one. Today this is only a written rule ("NEVER merge autonomously", Rule 16 batch pushes). Project-level allow lists defeat it: `Bash(git:*)`, `Bash(gh pr:*)`, `Bash(gh release:*)`, `Bash(gh api:*)` approve those commands without a prompt and, in auto mode, without the classifier.

This work adds user-level guardrails, installed by `install.sh`, that apply to every project on every server and that project settings cannot override.

This is phase 1 of a larger permission clean-up. Phase 2 (a shared allow list of safe commands for Java projects, and pruning the per-project `settings.local.json` files) is a separate design.

## 2. Goals, non-goals, anti-goals

**Goals**
- The operations in §4 always prompt (`ask`) or are always refused (`deny`), in the main session and in subagents, whatever the project settings allow.
- Common variants that plain Bash rules miss are still caught: options before the subcommand (`git -C <dir> push`, `gh -R <repo> pr merge`), absolute paths (`/usr/bin/git`), `bash -c '…'` / `sh -c '…'`, env-var prefixes, wrappers, compound commands.
- Rules are visible with `/permissions`; the hook is the backstop.
- `install.sh` stays idempotent and keeps the user's own `deny`/`ask` entries.

**Non-goals**
- A security boundary. Rules and the hook guard against an agent's mistakes, not against deliberate evasion. The Claude Code docs say so explicitly.
- GitHub-side enforcement (branch protection, rulesets). Protecting `main` would also block the direct-to-main commits the dev profile allows (`README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/HANDOFF*.md`).
- Local-only destructive commands (`git reset --hard`, `git clean -f`). The auto-mode classifier already evaluates them.
- The phase-2 allow list, `autoMode.classifyAllShell`, and the stale project-specific `autoMode` block in the user's `settings.json`.

**Anti-goals** (failure even if it "works")
- Prompting on harmless commands often enough that the user approves by reflex. Example: a rule `Bash(git * push *)` would prompt on `git commit -m "fix push retry"`.
- The hook ever returning `allow`. It only adds friction; it never removes it.
- `install.sh` silently deleting `deny`/`ask` entries the user added by hand.
- The hook breaking Bash entirely when it fails (a crash must not block every command silently, nor let everything through without saying so).

## 3. Verified facts (Claude Code docs, checked 2026-11-24)

Sources: `code.claude.com/docs/en/permissions.md`, `permission-modes.md`, `auto-mode-config.md`, `sub-agents.md`.

- Rules are evaluated `deny` → `ask` → `allow`; the first match wins and specificity does not matter. "If a tool is denied at any level, no other level can allow it." A matching `ask` prompts even when an `allow` also matches. So user-level `deny`/`ask` beat project `allow`. Managed settings are not needed.
- Auto mode: `deny` blocks before the classifier; an `ask` match cannot be auto-approved by the classifier; `allow` matches skip the classifier. By default the classifier allows pushing to any branch, including the default branch.
- Bash rules match the command text. `Bash(x *)` and `Bash(x:*)` are equivalent; the space form is current. Deny/ask apply when any subcommand of a compound command matches (`&&`, `||`, `;`, `|`, `&`, newlines, subshells, command substitution). Wrappers `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `noglob` and bare `xargs` are stripped before matching.
- Not matched by `Bash(git push *)`: `git -C . push`, `git -c k=v push`, `/usr/bin/git push`, `bash -c '…'`, `sh -c '…'`.
- Deny rules apply to subagents. PreToolUse hooks fire for subagent tool calls. A PreToolUse hook cannot override a deny/ask rule with `allow`, but a hook `deny`/`ask` applies even when an allow rule matches.

To confirm during implementation (against the installed Claude Code version): the PreToolUse hook output schema (`hookSpecificOutput.permissionDecision` = `ask` | `deny`, with `permissionDecisionReason`), and that `ask` rules apply inside subagents.

## 4. The policy (approved by the user, 2026-11-24)

**deny** — refused; the user can still run them with `!`:
- `gh repo delete`
- force push to `main` or `master` (`--force`, `-f`, `--force-with-lease`, `--force-if-includes`, or a `+` refspec, whose destination is `main`/`master`)

**ask** — prompt every time:
- any `git push` (includes `--tags`, remote branch deletion, force push to other branches)
- `gh pr merge`
- `gh release create | edit | delete | upload`
- `mvn deploy` / `./mvnw deploy` (any invocation whose goals include `deploy` or `deploy:deploy`), `docker push`
- `gh workflow run`, `gh secret set | delete | remove`, `gh variable set | delete`
- `gh api` that mutates: `-X`/`--method` other than `GET`, or any of `-f`, `-F`, `--field`, `--raw-field`, `--input` (gh switches to POST when fields are given)

**Deliberately out:** local `git tag` (becomes public only through `git push`, already covered), `gh pr create`, `gh issue edit`, local destructive commands (see §2).

## 5. Approaches

- **A. Rules only** (`permissions.deny`/`ask` in the settings fragment). Declarative and visible, minimal cost. Misses `bash -c`, absolute paths, options before the subcommand, and `gh api`.
- **B. Rules plus a PreToolUse guard hook** — **chosen by the user.** Rules give a visible first layer for the canonical forms; the hook parses the command and catches the variants, the `gh api` cases and the force-push-to-main deny.
- **C. Hook only.** One place for the logic, but invisible in `/permissions`.

## 6. Design

### 6.1 Rules (in `agents/claude/settings.fragment.json`, `enforce.permissions`)

Canonical forms only, no mid-pattern wildcards (see the anti-goal on over-prompting; the hook covers the variants):

- `deny`: `Bash(gh repo delete *)`
- `ask`: `Bash(git push *)`, `Bash(gh pr merge *)`, `Bash(gh release create *)`, `Bash(gh release edit *)`, `Bash(gh release delete *)`, `Bash(gh release upload *)`, `Bash(mvn deploy *)`, `Bash(./mvnw deploy *)`, `Bash(docker push *)`, `Bash(gh workflow run *)`, `Bash(gh secret set *)`, `Bash(gh secret delete *)`, `Bash(gh secret remove *)`, `Bash(gh variable set *)`, `Bash(gh variable delete *)`

Force push to `main` has no rule: its shapes are too varied for text patterns. The `git push` ask rule already prompts; the hook upgrades it to deny.

### 6.2 Guard hook

- File: `hooks/guard-irreversible.sh` in the repo (bash + `jq`; both are already installer prerequisites). Reached through the anchor as `~/.agent-dotfiles/hooks/guard-irreversible.sh`.
- Registered in `enforce.hooks.PreToolUse` with matcher `Bash`, alongside the existing Serena hooks.
- Input: the PreToolUse JSON on stdin; it reads `tool_input.command`. Any other tool → exit 0, no output.
- Output: for a match, the PreToolUse decision JSON with `ask` or `deny` and a one-line reason naming the matched policy item (e.g. `guard: gh pr merge needs user confirmation`). No match → exit 0, no output. Never `allow`.
- Most severe wins: if one segment is `deny` and another `ask`, the result is `deny`.

Normalisation, per segment:
1. Split the command on `&&`, `||`, `;`, `|`, `&` and newlines. A quote-aware split is preferred; an approximate split is acceptable if the tests in §6.4 pass.
2. For `bash -c '<s>'` / `sh -c '<s>'` (also with `-lc`, `-ec` and similar flag clusters ending in `c`), recurse into `<s>`.
3. Strip leading `NAME=value` assignments and the wrappers `env`, `sudo`, `timeout <n>`, `time`, `nice [-n <n>]`, `nohup`, `stdbuf <opts>`, `command`, `builtin`, `exec`, `xargs`.
4. Reduce the program to its basename (`/usr/bin/git` → `git`, `./mvnw` → `mvnw`).
5. Skip global options before the subcommand: for `git`, `-C <dir>`, `-c <k=v>`, `--git-dir[=]<x>`, `--work-tree[=]<x>`, `--namespace[=]<x>`, `--no-pager`, `-P`, `--bare`, `--no-replace-objects`; for `gh`, `-R`/`--repo <x>`, `--hostname <x>`.

Classification after normalisation follows §4. For the force-push deny: the push is forced if any flag is `--force`, `-f` (also inside a short-flag cluster such as `-fu`), `--force-with-lease[=…]`, `--force-if-includes`, or any refspec starts with `+`. The destination is `main`/`master` if a refspec's destination (the part after `:`, or the whole refspec without `:`) is `main`, `master`, `refs/heads/main` or `refs/heads/master`. When a forced push has no refspec (it pushes the current branch), the destination is unknown → `ask`, not `deny` (builder's call recorded here: no git calls from the hook, it stays a pure text check).

Failure handling: if `jq` is missing or the stdin JSON cannot be parsed, emit `ask` with reason `guard: hook error, confirm manually` when possible, or exit 0 and print the error to stderr when even that is impossible. Never exit 2 on an internal error.

### 6.3 Installer: union merge for permission lists

`merge_settings` currently does `$local * $enforce`, which replaces arrays. For `permissions.deny`, `permissions.ask` and `permissions.allow`, the merged value becomes the local list followed by the enforce entries that are not already in it (order kept, no duplicates). The other `enforce` keys keep today's semantics, and `hooks` is still replaced as a whole. Change reporting (`changed: settings.<key>`) keeps working.

Known limitation (accepted): when a later version of the policy drops a rule, the old entry stays in the user's `settings.json`, because the union merge cannot tell it apart from a hand-added one. Removing it is a manual step, to be noted in the release notes of that change.

### 6.4 Tests

- `tests/test_guard_hook.sh` (new), table-driven, feeding PreToolUse JSON to the script and checking the decision. It must include:
  - deny: `gh repo delete x/y --yes`, `git push --force origin main`, `git push -f origin HEAD:main`, `git push origin +main`, `git -C /tmp/r push --force-with-lease origin master`, `bash -c "git push -f origin main"`
  - ask: `git push`, `git push origin feat/x`, `git push --force origin feat/x`, `git push --force` (no refspec), `git push origin --delete feat/x`, `git -C . push`, `/usr/bin/git push`, `FOO=1 git push`, `timeout 30 git push`, `cd x && git push`, `gh pr merge 12 --squash`, `gh -R o/r pr merge 12`, `gh release create v1.0.0`, `mvn -B deploy`, `./mvnw clean deploy -DskipTests`, `docker push ghcr.io/x/y:1`, `gh workflow run ci.yml`, `gh secret set TOKEN`, `gh api -X DELETE repos/o/r/git/refs/heads/x`, `gh api repos/o/r/pulls/1/merge -f merge_method=squash`, `sh -c 'gh pr merge 1'`
  - no decision: `git status`, `git log --oneline`, `git commit -m "fix push retry"`, `echo "git push"`, `gh pr view 12`, `gh pr create --fill`, `gh api repos/o/r/pulls`, `gh release view v1`, `mvn -B verify`, `docker pull x`, `gh secret list`, `git tag v1.0.0`
  - error path: invalid JSON → `ask` (or no decision with stderr), never exit 2
- `tests/test_install_settings.sh`: cases for the union merge (a user `deny` entry survives; no duplicates on a second run; idempotent second run reports `unchanged`).

### 6.5 Documentation

`README.md`: a short section on the guard (what is denied, what asks, how to run a blocked command with `!`, the "not a security boundary" caveat).

## 7. Left to the builder

- Exact parsing technique in the hook (pure bash vs a small `jq`/`awk` tokenizer), as long as §6.4 passes and the hook stays fast (no network, no git calls).
- Exact wording of the reasons.
- Test harness details (reuse `tests/lib.sh`).
