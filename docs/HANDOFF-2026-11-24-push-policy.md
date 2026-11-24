# HANDOFF — 2026-11-24 — push policy (in flight) and issue #14 migration

Written to resume after a context reset. Conversation language with the user: Italian. Artifacts: English.
Not yet committed. Open question for the user: commit it to `main` directly (the docs-only exception covers `docs/HANDOFF*.md`, not a root `HANDOFF-*.md` — move it to `docs/` first) or keep it local.

## 1. In flight: push policy (branch `feat/push-policy`, dev clone `/home/sramazzina/work/serasoft/agent-dotfiles`)

User rule: agents push feature branches freely; pushes to `main`/`master` or to the `upstream` remote only when the user explicitly asks, then without a further prompt. Docs-only pushes to `main` (README.md, CLAUDE.md, CHANGELOG.md, docs/HANDOFF*.md — dev profile exception) stay free. Force push / deletion of `main`/`master` denied. Everything else in the guard (merge, release, deploy, secrets, mutating `gh api`) unchanged.

- Spec (approved): `docs/superpowers/specs/2026-11-24-push-policy-design.md` (approach A: auto-mode classifier + `classifyAllShell: true`; hook resolves push destinations with local read-only git; in auto mode the hook gives no decision for protected pushes, in other modes it asks).
- Plan: `docs/superpowers/plans/2026-11-24-push-policy.md` — 2 tasks. Issues: #23 (Task 1, hook), #24 (Task 2, settings/autoMode/docs).
- Execution: subagent-driven. SDD ledger (git-ignored): `.superpowers/sdd/2026-11-24-push-policy/progress.md` — read it and `references/resuming.md` of the subagent-driven-development skill before continuing. Task reports: `.superpowers/sdd/2026-11-24-push-policy/task-1-report.md`.
- **UPDATE (2026-11-24, 16:45): PRs #26 and #27 MERGED; issues #23, #24, #25 closed. Cutover done on this machine:** `~/.agent-dotfiles` at `57ed74e`; installer run (backup `~/.agent-dotfiles-backups/20261124-164508/`); `Bash(git push *)` removed from `permissions.ask`; stale `autoMode` block removed with the user's approval (now only `$defaults` + push rule, `classifyAllShell: true`); second install idempotent. Local branches, escalation worktree and SDD workspace deleted. **Live checks:** 4 and 9 (default mode asks) PASSED; auto mode with explicit request runs without prompt (8) PASSED. **Still open:** checks 5, 6, 7, 10; remote branches `feat/push-policy` and `feat/model-escalation-ask` still exist on origin. The lines below describe the state before the merge.
- **Status (pre-merge): PR #27 open** (`Closes #23`, `Closes #24`), branch pushed. Tasks 1 and 2 complete and reviewed; final whole-branch review (Opus) → one fix wave (`33c93d2`: `heads/main` deny bypass, xargs, `push.default`/`remote.<r>.push`, pushRemote order, docs) → scoped re-review clean. Full suite 93 PASS / 0 FAIL. Rulings and parked minors: listed in the PR body and the SDD ledger.
- **Next action: wait for the user's literal `merged`**, then cutover (below), then delete the SDD workspace `.superpowers/sdd/2026-11-24-push-policy/` and the local branch.
- Separate PR #26 (issue #25, branch `feat/model-escalation-ask`, worktree `/home/sramazzina/work/serasoft/agent-dotfiles-escalation`): global rule "ask the user before escalating to a more capable model". After merge: `git pull` in `~/.agent-dotfiles`, remove the worktree, delete the branch. Standing approval already given: SDD final whole-branch review on Opus (auto-memory `final-review-most-capable-model`).
- **Cutover (after merge)**, on this machine: `git pull` in `~/.agent-dotfiles`; `./install.sh --dry-run`, then `./install.sh`; manually remove `Bash(git push *)` from `permissions.ask` in `~/.claude/settings.json` (union merge keeps it); show the user the stale `autoMode` block (iceberg-platform-poc `environment` + 2 `soft_deny` entries) and remove it with their approval; user runs the live checks added to `docs/verification.md`.

## 2. Done today

- **PR #22 merged** (irreversible-operations guard: hook `hooks/guard-irreversible.sh`, deny/ask rules, union merge of permission lists). Installed on this machine; the three live checks passed. Branch deleted.
- **Issue #14 (server migration), this machine:** `~/.agent-dotfiles` is a separate clone of `main` (installer run, idempotent; old `~/.claude/CLAUDE.md` backed up to `~/.agent-dotfiles-backups/20261124-065539/`). `/memory` check passed.
  - Dev profile enabled (`--enable-dev`) and project `CLAUDE.md` fixed and pushed: **cardine** (`611bc25`; plus local unpushed handoff commit `145c59e` that must ride with the #118 branch — see cardine `docs/HANDOFF-2026-11-24-anchor-fix-resume.md`), **hop-opentelemetry-plugin** (`0e1e7c3`), **data-loader-v2** (`56795e9`, `d4667ff`).
  - User decisions: copyright header stays per project (new files use 2026 in data-loader-v2); Rules 17/18 stay in cardine; Rule 3 from AGENTS.md wins.

## 3. Open items (in order the user may pick)

1. Continue #14 with the next project on this machine — **the user gives the projects one at a time; do not proceed on your own**. Per project: dry-run `--enable-dev`, analyse its CLAUDE.md vs the layers (subagent), propose, act on approval.
2. Unification list → one issue + PR into `profiles/dev.md`: strict merge guard (proceed with post-merge cleanup only on the literal answer `merged`; never infer a merge from silence, topic change, absence of an error, or ambiguous `gh pr view`); `git pull` of `main` at the start of each task. After promotion, trim cardine Rule 19 accordingly.
3. Phase 2 of permissions: shared safe allow list for Java projects (much less valuable in auto mode once `classifyAllShell` ships), prune per-project `.claude/settings.local.json` (data-loader-v2 holds a hard-coded API key in a curl entry).
4. Close #14: comment with server, date, enabled projects; tick checklist; update handoff notes.
5. Deferred minors: guard `mvn -pl deploy verify` false ask; `docker -H x push` not caught; README `gh api` bullet lacks `--method`; hop-opentelemetry-plugin `docs/guides/tech/release-process.md` line 53 cites `hop-parquet-plugin`.
