# Development profile

Rule numbers are global across all layer files and never change; Rule 6 is retired.

## Rule 2 — Simplicity First
Minimum code that solves the problem. Nothing speculative. No features beyond what was asked. No abstractions for single-use code. Test: would a senior engineer say this is overcomplicated? If yes, simplify.
## Rule 8 — Read before you write
Read exports, immediate callers, shared utilities first. "Looks orthogonal" is dangerous. If unsure why code is structured a way, ask.
## Rule 9 — Tests verify intent
Tests encode WHY behavior matters. A test that cannot fail when the business logic changes is wrong.
## Rule 11 — Match the codebase's conventions
Conformance > taste. Surface conventions you think harmful; don't fork silently.
## Rule 13 — No dismissed or unmaintained dependencies
Before adopting a library/framework/plugin/tool, verify upstream activity (recent releases and commits, issue triage, deprecation notices). If archived, slow-maintenance, or superseded, say so before proposing it and pick the maintained successor. Flag existing ones for replacement instead of working around their bugs.
## Rule 14 — Avoid GPL-licensed code
No GPL-family dependencies, snippets, or assets (GPLv2/v3, AGPL, statically linked LGPL, any propagating copyleft). Verify every third-party component is permissive (Apache 2.0, MIT, BSD, MPL 2.0 file-scope, EPL 2.0, …); if not, surface it and propose a permissive alternative. When in doubt, ask.
## Rule 16 — Contain CI cost: defer push, batch commits
Every push to a PR branch or a CI-triggering branch fires the full workflow matrix. Applies to any delegated worker too: they commit locally and report; they never push.
1. Open the PR last: accumulate task commits locally, verify each with the project's local test suite; open the PR when implementation is complete or when a CI-only check (one this machine can't run) is the blocker.
2. Batch pushes (2–3 commits per push) and batch CI fixups into one push.
3. Before pushing, squash WIP commits ("typo", "fix compile") into their task commit; keep one task = one commit.
4. When pushing, state what is pushed and why, so CI cost is auditable.
5. Exceptions: branch protection requiring a green run; user asks to push; direct-to-main files (see Git and PR rules).

# Sprints, issues, tests
- Work is organized in sprints; each plan Task is a GitHub Issue that the agent creates (`gh issue create`, before execution, one per Task) — never ask the user to open them. Body: objective + `- [ ]` checklist.
- Tick each checklist item (`gh issue edit`) as soon as it's implemented and committed. All items MUST be `- [x]` before opening a PR or declaring a task done.
- Every feature/bugfix ships with tests; tests must pass (in CI) before merging. Plain DTOs or integration-only code (live-DB adapters, headless-untestable UI) may rely on covering tests — say so in the plan and make sure they exist.
- Commit work plans and design specs to git.

# Git and PR rules
- Every code change on a dedicated branch, merged to `main` via PR. Exception: `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/HANDOFF*.md` go directly to `main` (no branch, PR, or issue).
- Group correlated issues (same theme AND overlapping files) into one PR by default; open separate PRs only when the work is truly independent. Propose the grouping and confirm first. One task = one commit inside it. PR body has `Closes #N` for every grouped issue.
- Technical/operational docs for a feature go on that feature's branch/PR (not direct-to-main, not a separate PR while it's open); only after merge does a follow-up PR carry them.
- The agent creates PRs; the user merges — NEVER merge autonomously. Only after the user confirms the merge: delete the branch locally and on the remote, checkout `main`, pull.
