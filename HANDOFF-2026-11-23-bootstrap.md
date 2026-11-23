# Handoff — agent-dotfiles (updated 2026-11-23, after PR #12 merge)

Read this section first, then continue with the user in Italian (global Language Rules). The original bootstrap handoff is kept below as history; its open questions are all resolved.

## Current state
- Repo: `git@github.com:sramazzina/agent-dotfiles.git` (private, solo). Local clone: `/home/sramazzina/work/serasoft/agent-dotfiles`. Renamed from `claude-config` to reflect the multi-agent goal (Claude Code now; opencode, pi, goose later).
- `main` = `425899a` (merge of PR #10, "agent-dotfiles core"). Feature branch deleted locally and on the remote. Issues #3–#9 closed by the merge.
- Delivered: layered rules (`AGENTS.md` neutral universal, `profiles/dev.md` neutral dev, `rules/java.md` path-scoped, `agents/claude/{CLAUDE.md,dev.md}` Claude-only), skill `serena-query-project`, `mcp/servers.json` (context7, serena), `agents/claude/settings.fragment.json` (enforce + seed), idempotent `install.sh` (`--dry-run`, `--enable-dev <dir>`, `--help`), 53 bash tests (`bash tests/run.sh`), README, adapter notes for opencode/pi/goose.
- Authoritative docs: `README.md` (usage, summary-line prefixes, exit codes), `docs/superpowers/specs/2026-11-23-agent-dotfiles-design.md` (design), `docs/superpowers/plans/2026-11-23-agent-dotfiles-core.md` (executed plan), `docs/verification.md` (verified Claude Code behaviour: `@~` imports, user rules via symlink incl. on file creation, skills via symlink).
- `drafts/global-CLAUDE.md.proposed` is superseded by the layer files; it can be deleted.
- GitHub labels: `type:*`, `area:*`, `priority:P0`–`P3` (default labels removed).
- PR #12 (squash-merged, `main` = `1878e4a`; closed #11, #13): `AGENTS.md` gained an ASD-STE100 (Simplified Technical English) style bullet under "Language and tone"; the `## Rule 6 — (retired; number reserved)` heading was removed WITHOUT renumbering (user decision: project docs, e.g. ~20 files in cardine, cite rules by number). Layer headers still say "Rule 6 is retired"; `tests/test_rules.sh` expects 1–16 without 6. The Documentation section is now two bullets (agent-consumed / human-consumed).
- Discussed, no action yet: (a) the Claude model-routing text in the universal layer uses dev wording ("production or test code") — candidate to neutralise and move the dev part to `agents/claude/dev.md`; (b) the dev profile is all-or-nothing (assumes GitHub issues/PRs/Actions) — split into a core + "GitHub workflow" module only if a non-GitHub dev project appears.

## Rulings made during execution (user informed, not yet explicitly confirmed)
1. `failed: <what>` summary prefix for hard failures (exit 1), distinct from `skipped:` (step not attempted).
2. A symlinked `~/.claude/settings.json` is written through to its target (link kept, target mode preserved); a dangling link is `failed:`.

## Known minor gaps (accepted as-is)
pi NOTES lacks config details; write-failure branches of `install.sh` untested; `ccstatusline@latest` unpinned in the settings fragment; `CONTEXT7_API_KEY` briefly visible in argv during the first `claude mcp add` (CLI limitation, documented).

## Next step: cutover on this machine (not started) — tracked in issue #14
The live `~/.claude` is still the pre-project configuration. Issue #14 tracks the migration of all servers (procedure, per-server checklist; the server list must be confirmed with the user). Do it together with the user:
1. `cd /home/sramazzina/work/serasoft/agent-dotfiles && ./install.sh --dry-run`; review every line with the user.
2. `export CONTEXT7_API_KEY=...` only if context7 is not already registered (on this machine it is: expect `mcp-ok`). `./install.sh`. Expected: `~/.claude/CLAUDE.md` backed up to `~/.agent-dotfiles-backups/<ts>/` and linked; settings unchanged (mode 600, `autoMode` kept); `mcp-ok` for both servers; a second run is all `unchanged:`/`mcp-ok:`.
3. Start a fresh Claude session and check `/memory` (universal layer imported via `~/.agent-dotfiles/AGENTS.md`).
4. Expected gap: dev projects lose the dev rules until `~/.agent-dotfiles/install.sh --enable-dev <project>` is run in each; ask the user which projects, run it, and have them accept the one-time external-import dialog in each (declining disables the import permanently for that project).
5. Repeat steps 1–4 on the other Linux servers (clone to `~/.agent-dotfiles` or anywhere; the installer creates the anchor).

## Deferred (open issues)
- #1 Generic migration path for existing projects (remove per-project duplicates of the global rules; keep deliberate opt-outs). Must be generic — projects live on other servers too. Audit context from this machine is in the issue.
- #2 Plan B: per-language rules imported at session start (`--enable-dev --lang`). Verification showed path-scoped rules also trigger on file creation, so it is probably unnecessary.

## Gotchas
- `gh issue view` fails on a deprecated Projects field; use `gh api repos/sramazzina/agent-dotfiles/issues/<n>`.
- opencode falls back to `~/.claude/CLAUDE.md` and would inherit Claude-only rules: when adding its adapter, give it its own AGENTS.md or set `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1`.
- `settings.json` must stay a real local file (Claude Code writes `/model` changes back); never version it, nor `~/.claude.json`.

---

# History: original bootstrap handoff

## Handoff — bootstrap of `claude-config` (2026-11-23)

Origin: a `/doctor` + CLAUDE.md cleanup session run from `/home/sramazzina/work/serasoft/cardine`. The user decided to materialize the idea below as its own project in this folder. Read this file first, then continue the conversation with the user (in Italian, per the global Language Rules).

## Goal
A private git repo holding the user's personal Claude Code configuration, cloned on every Linux machine where agents run and linked into `~/.claude` by an install script, so the same layered rules apply to every project on every machine.

## Operating model (stated by the user)
- Claude Code agents run on **remote Linux servers**.
- The user orchestrates them from **Windows** via **herdr** (terminal multiplexer for coding agents, https://github.com/ogulcancelik/herdr). Herdr `--remote` runs the server on the Linux host and the client locally over SSH; the client has its own `~/.config/herdr/config.toml`.
- Consequence: `~/.claude` config is needed on the **Linux servers only** → `install.sh` can be plain bash; no Windows symlink handling (unless the user later runs Claude Code on Windows too).
- Not verified: whether herdr orchestrates agents across hosts natively. Community add-ons exist (herdr-orchestra, herdr-orchestrator-skill, herdr-claude-teams) — unvetted; apply global Rule 13 (maintenance check) and Rule 14 (license) before adopting any.

## Agreed design direction (user approved the model, details still to design)
Three layers:

| Layer | Location | Content | Activation |
|---|---|---|---|
| Universal | `~/.claude/CLAUDE.md` | Rules valid for NON-development projects too: Rules 1, 3, 4, 5, 7, 10, 12, model routing, language & tone, documentation format | always |
| Development | `~/.claude/profiles/dev.md` | Rules 2, 8, 9, 11, 13–16, sprints/issues, git/PR, Serena, tests | explicit `@~/.claude/profiles/dev.md` import per dev project (in `CLAUDE.local.md` for shared repos) |
| Language | `~/.claude/rules/java.md`, `python.md`, … | language-specific commands/conventions (Maven, Testcontainers, `pom.xml`, …) | user-level path-scoped rules (`paths:` frontmatter), auto-loaded when touching matching files |

Rationale for the split: dev-workflow rules (branching, PR-last) must be in force from session start, so they are imported explicitly, not path-scoped. The rule-to-layer split in the table is a proposal — confirm with the user.

Proposed repo layout:
```
claude-config/
├── CLAUDE.md            → symlink ~/.claude/CLAUDE.md
├── profiles/dev.md      → imported with @ in dev projects
├── rules/*.md           → symlink into ~/.claude/rules/
├── skills/serena-query-project/SKILL.md → symlink into ~/.claude/skills/
└── install.sh           idempotent; backs up existing files; checks (does not install) prerequisites
```
Never version: `~/.claude.json` (tokens, project history), `.credentials.json`, transcripts, plugin caches. `settings.json`: handle cautiously (secrets can land in `env`); today it holds `env.CLAUDE_CODE_SUBAGENT_MODEL=sonnet`, `permissions.defaultMode=auto`, `skillOverrides`, `enabledPlugins`, and serena hooks (`serena-hooks activate|remind|auto-approve|cleanup`).

Per-server manual prerequisites (script should check and report): Claude Code login, `gh auth login`, serena + `serena-hooks` installed, `uvx`.

## Verify before building (docs, not memory)
1. `@~/...` imports from CLAUDE.md work, including from a symlinked CLAUDE.md, and the first-use import approval behavior.
2. User-level path-scoped rules in `~/.claude/rules/` with `paths:` frontmatter are supported in the installed version (2.1.330), and whether they trigger when a matching file is being *created*.
3. Claude Code follows symlinks for `~/.claude/CLAUDE.md`, `~/.claude/rules/`, `~/.claude/skills/`.

## Starting material
- `drafts/global-CLAUDE.md.proposed` — compacted global CLAUDE.md (156→77 lines, 19.2k→8.2k chars), NOT yet applied to `~/.claude/CLAUDE.md`. It is a single-file version: it must now be split into the universal layer + `profiles/dev.md` (+ language rules). It already moves the Serena `query_project` procedure out to a skill `serena-query-project` (procedure text = current `~/.claude/CLAUDE.md` section "Using Serena `query_project` on another project", to be copied verbatim).
- Live `~/.claude/CLAUDE.md` is the source of truth for exact rule text.

## State of `~/.claude` after the origin session (already applied)
- Rules 1–16 unified in `~/.claude/CLAUDE.md` with the same numbering cardine uses (Rule 6 retired, number reserved; GPL = Rule 14; MCP tools for implementers = Rule 15; CI cost = Rule 16). Numbers are referenced from project docs — never renumber.
- Added "Model Routing — MANDATORY" section (Opus = architect/judge/orchestrator only; hands-on work → Sonnet subagents).
- `~/.claude/settings.json`: `env.CLAUDE_CODE_SUBAGENT_MODEL=sonnet`; `skillOverrides` turning off 11 unused `~/.claude/commands`. `~/.claude.json`: `autoUpdates=true`.
- Backups: `~/.claude/CLAUDE.md.bak-doctor`, `~/.claude/settings.json.bak-doctor`, `~/.claude.json.bak-doctor` (pre-session state).
- cardine's `CLAUDE.md` now holds only Rules 17–19 + copyright header (uncommitted in cardine's working tree — not this project's concern).

## Open questions for the user
1. Repo host: personal GitHub account or SeraSoft org (private either way)?
2. Solo repo, or future shared baseline for colleagues?
3. Confirm the rule-to-layer split above.
4. Version `settings.json` (or a fragment merged by `install.sh`) or keep it per-machine?

## Next steps
Per global rules: `superpowers:brainstorming` to finish the design (approaches → short design doc → user approval), then `superpowers:writing-plans`, then subagent-driven execution. `git init` this folder as part of that work.
