# agent-dotfiles — Design

Date: 2026-11-23 · Status: approved by the user (2026-11-23)
Origin: `HANDOFF-2026-11-23-bootstrap.md` (project was bootstrapped as `claude-config`, renamed to `agent-dotfiles` in this session).

## 1. Intent

A private git repo holding the user's personal coding-agent configuration: behavioral rules, skills, and MCP server definitions. It is cloned on every Linux server where agents run and wired into each agent's home configuration by an install script, so the same layered rules apply to every project on every machine.

Today the only agent in use is **Claude Code**. The user wants the repo shaped so that **opencode, pi and goose** can be added later, sharing the same rules, skills and MCP servers, without restructuring.

Operating model: agents run on remote Linux servers; the user drives them from Windows via herdr (`--remote`, client over SSH). Configuration is needed on the Linux servers only → `install.sh` is plain bash; no Windows support.

## 2. Goals, non-goals, anti-goals

**Goals**
- One source of truth for rules, skills and MCP definitions, versioned in git.
- Rules split along two axes: *universal vs development* and *agent-neutral vs agent-specific*.
- Claude Code fully wired today using its native mechanisms (symlinks, `@` imports, path-scoped rules, user-scope MCP).
- Adding another agent later = adding one adapter directory + an install step, no change to the neutral content.
- `install.sh` idempotent, safe (backs up anything it replaces), and able to report missing prerequisites.

**Non-goals**
- Adapters for opencode / pi / goose (only documented notes now — Rule 2).
- Sharing with colleagues (repo is personal for now).
- Installing prerequisites (Claude Code login, `gh`, serena, `uvx`) — check and report only.
- Windows / macOS support.
- Versioning `~/.claude/commands/` (11 legacy commands, already disabled via `skillOverrides`).
- Migrating existing projects (removing duplicated rules, preserving opt-outs, handling upstream clones) — deferred to its own design: issue #1. This work only provides the mechanical `--enable-dev` building block.

**Anti-goals** (failure even if it "works")
- Secrets or machine/project-specific data landing in the repo (`~/.claude.json`, `.credentials.json`, transcripts, plugin caches, the project-specific `autoMode` block in today's `settings.json`).
- Rule numbers changing. Rules 1–16 are referenced by number from project docs; Rule 6 stays retired/reserved.
- Dev projects silently losing the dev rules after cutover (see §8).
- Claude-only instructions (Opus/Sonnet routing, superpowers) leaking into another agent's context.

## 3. Constraints and verified facts

From official docs, checked 2026-11-23 (Claude Code 2.1.330 installed):
- `@~/...` imports work in user and project memory files. User-scope imports load without a dialog; external imports in a project file trigger a one-time approval dialog per project (declining disables them permanently for that project). Max import depth: 4 hops. Relative imports resolve against the importing file; behaviour through a symlinked file is **not documented**.
- `~/.claude/rules/*.md` is supported; `paths:` frontmatter works at user level, with globs matched against the session's primary working directory. A path-scoped rule loads on Read/Write/Edit of a matching file; loading on *creation* of a new file is not explicitly documented. Rules without `paths:` load at launch.
- `~/.claude/skills/<name>` may be a symlink to a directory elsewhere. `~/.claude/skills/synced` is reserved (claude.ai-synced skills) — never touch it.
- A symlinked `CLAUDE.md` is read through the link; Edit/Write tools refuse to write through symlinks (edits land on the repo file — desired).
- `settings.json` has no include/merge mechanism. Claude Code writes UI changes (e.g. `/model`) back to `~/.claude/settings.json` → it must stay a real, writable local file.
- MCP servers (`context7`, `serena`) are user-scope entries in `~/.claude.json` (not versionable) → registered via `claude mcp add --scope user`.
- Other agents (for future adapters): all read `AGENTS.md` and the Agent Skills `SKILL.md` format. Global files: opencode `~/.config/opencode/AGENTS.md` (falls back to `~/.claude/CLAUDE.md` if absent), pi `~/.pi/agent/AGENTS.md` (no import syntax), goose `~/.config/goose/.goosehints` (`@file` imports). Skills: opencode and goose read both `~/.claude/skills` and `~/.agents/skills`; pi reads `~/.agents/skills`. All three are MIT/Apache-2.0 and actively released (Nov 2026).

Global rules applying to this repo: all artifacts in English; Rule 13/14 for any tool adopted; agent-consumed docs in Markdown.

## 4. Approaches considered

1. **Native per-agent entry files** — each agent gets a hand-written entry file importing shared fragments with its own mechanism (`@` for Claude/goose, `instructions` array for opencode). Clean and live-editable, but pi has no import syntax, and it means building three adapters for agents not in use.
2. **Generator for all agents** — `install.sh` concatenates fragments into each agent's instruction file. Uniform (covers pi), but every rule edit needs a re-run, Claude loses path-scoped language rules, and generated files invite accidental edits.
3. **Hybrid (chosen by the user)** — Claude Code uses its native mechanisms now; the repo content is organised agent-neutrally; other agents get a notes file only. Future adapters pick native wiring or generation per agent.

Why 3: it does the expensive-to-change-later part now (separating neutral from Claude-specific rules) without speculative adapters.

## 5. Design

### 5.1 Repo layout

```
agent-dotfiles/
├── README.md                     what it is, install, how to enable the dev profile in a project
├── AGENTS.md                     neutral universal rules (always on, any agent)
├── profiles/
│   └── dev.md                    neutral development rules
├── rules/
│   ├── java.md                   language rules; content neutral, `paths:` frontmatter for Claude
│   └── python.md
├── skills/
│   └── serena-query-project/SKILL.md
├── mcp/
│   └── servers.json              neutral MCP manifest
├── agents/
│   ├── claude/
│   │   ├── CLAUDE.md             Claude entry: imports AGENTS.md + Claude-only universal rules
│   │   ├── dev.md                Claude dev entry: imports profiles/dev.md + Claude-only dev rules
│   │   └── settings.fragment.json
│   ├── opencode/NOTES.md         findings + requirements for a future adapter
│   ├── pi/NOTES.md
│   └── goose/NOTES.md
├── install.sh
├── tests/                        install.sh tests
└── docs/superpowers/{specs,plans}/
```

Naming: the neutral core is `AGENTS.md` at the repo root (the cross-agent standard name). Agent-specific entries live under `agents/<agent>/`.

### 5.2 Stable anchor path

`install.sh` creates `~/.agent-dotfiles` → symlink to the clone, wherever it was cloned. All imports use this anchor (e.g. `@~/.agent-dotfiles/AGENTS.md`). Reason: avoids relying on undocumented relative-import resolution through symlinked files, and frees the clone location.

### 5.3 Rule-to-layer split

| | Neutral | Claude-only |
|---|---|---|
| **Universal** (always on) — `AGENTS.md` / `agents/claude/CLAUDE.md` | Rules 1, 3, 4, 5, 7, 10, 12 · language & tone · documentation format (Markdown/HTML+SVG, Mermaid, Draw.io) | Model routing (Opus architect / Sonnet subagents) · workflow skills (superpowers brainstorming, writing-plans) |
| **Development** (per-project opt-in) — `profiles/dev.md` / `agents/claude/dev.md` | Rules 2, 8, 9, 11, 13, 14, 16 · sprints, issues, tests · git & PR rules | Rule 15 (implementer prompts use Serena/context7) · subagent-driven plan execution · Tools section (context7, Serena, `serena-query-project` skill) · Bash chaining rule |
| **Language** — `rules/*.md` (superseded by `2026-11-25-language-layer-import-design.md`: now `languages/<lang>.md`, imported per project) | rule content | `paths:` auto-activation |

- Each file keeps the rule numbers; a short header line in each layer file states that numbering is global across layers, Rule 6 is reserved, and numbers must never change.
- Cross-layer references (e.g. Rule 4 → Rule 16, subagent-driven execution) are kept as-is; they are harmless when the referenced layer is not loaded.
- **Rule text source** (my call): the compacted wording in `drafts/global-CLAUDE.md.proposed`, cross-checked against the live `~/.claude/CLAUDE.md`. Tie-break: if the draft dropped an obligation present in the live file, the live obligation wins (re-added in compact form). The user reviews the resulting text in the PR diff.
- The `serena-query-project` skill body is the live section "Using Serena `query_project` on another project", verbatim.
- **Commit hygiene goes in the universal neutral layer** (my call): "no co-author references, no 'Generated with …' footer in commits/PRs" applies to any git work, including non-dev projects. The rest of the git/PR rules (branches, PR flow, direct-to-main exceptions, issue grouping) stay in dev.
- **Language rules** (superseded by `2026-11-25-language-layer-import-design.md`) (my call): create a real `rules/java.md` holding the Java/Maven specifics now embedded as examples in Rule 16 and the testing section (`mvn -pl <module> -am -DskipITs verify`, Testcontainers ITs needing a Docker socket). Rule 16 keeps a generic wording ("verify with the local test suite") and keeps its number. `paths:` globs: `**/*.java`, `**/pom.xml`. No `python.md` until there is content — no empty placeholders.

### 5.4 Claude Code wiring (what `install.sh` does)

| Target | Action |
|---|---|
| `~/.agent-dotfiles` | symlink → clone |
| `~/.claude/CLAUDE.md` | symlink → `agents/claude/CLAUDE.md` (which imports `@~/.agent-dotfiles/AGENTS.md`) |
| `~/.claude/profiles/dev.md` | symlink → `agents/claude/dev.md` (which imports `@~/.agent-dotfiles/profiles/dev.md`) |
| `~/.claude/rules/<file>.md` (superseded by `2026-11-25-language-layer-import-design.md`: no longer linked) | per-file symlink → `rules/<file>.md` (per-file, not the whole directory, so local rules can coexist) |
| `~/.claude/skills/<name>` | per-skill symlink → `skills/<name>`; `synced/` untouched |
| `~/.claude/settings.json` | real file; `settings.fragment.json` deep-merged in with `jq` (fragment wins on its own keys; all other keys untouched) |
| MCP servers | for each entry in `mcp/servers.json`: `claude mcp add --scope user` if missing; if present with a different definition, report drift and leave it (no silent overwrite) |

`settings.fragment.json` contains (my call) two groups:
- **enforced** (fragment wins on every run): `env.CLAUDE_CODE_SUBAGENT_MODEL`, `permissions.defaultMode`, the serena hooks, `statusLine`, `enabledPlugins`, `extraKnownMarketplaces`, `skillOverrides`. `hooks` is replaced as a whole (merging hook arrays is ambiguous).
- **seeded** (written only when the key is absent, never overwritten, because Claude Code writes `/model` etc. back to the file): `model`, `effortLevel`.

It never contains `autoMode` (project-specific today) or anything secret. An enforced key that changes an existing value is reported in the summary.

`statusLine` runs `npx -y ccstatusline@latest`: `node`/`npx` join the prerequisite check, and the floating `@latest` is flagged under Rule 13 (pinning a version is a follow-up decision, not part of this work).

Skills are linked into `~/.claude/skills/` only — not `~/.agents/skills/` — because opencode and goose read both and could load duplicates. Future adapters decide.

### 5.5 `mcp/servers.json`

Neutral list: per server a name, transport (`stdio` / `http`), command+args or URL, and an optional per-agent override block. Today (matches `claude mcp list` on this machine, 2026-11-23): `context7` (http, `https://mcp.context7.com/mcp`) and `serena` (stdio, `serena start-mcp-server --project-from-cwd`, with Claude override `--context claude-code`; live command line is `serena start-mcp-server --context claude-code --project-from-cwd`). The builder confirms with `claude mcp get <name>` before writing the manifest so the first install reports no drift. No secrets: any credential is referenced by env-var name, never stored.

### 5.6 `install.sh` behaviour

- Bash, `set -euo pipefail`, idempotent: a target already pointing to the right place is a no-op.
- Before replacing an existing file/link, moves it to `~/.agent-dotfiles-backups/<timestamp>/` preserving relative path.
- `--dry-run` prints planned actions without changing anything (my call: cheap, and the script rewrites `~/.claude`).
- Prerequisite check (report, non-fatal unless needed for a step): `git`, `jq`, `claude` (+ logged in), `gh auth status`, `serena`, `serena-hooks`, `uvx`. `jq` and `claude` are required for the settings/MCP steps; if missing, those steps are skipped and reported loudly (Rule 12), and the exit code is non-zero.
- Ends with a summary: linked / unchanged / backed up / skipped / drift.
- Only the Claude adapter is implemented; structure leaves room for `--agent <name>` later, but no flag is added now.
- **`--enable-dev <project-dir>`** (user's choice): enables the dev profile for one project. It ensures `<project-dir>/CLAUDE.local.md` contains the line `@~/.claude/profiles/dev.md` (creating the file if absent, appending if missing, no-op if present) and that `CLAUDE.local.md` is ignored when the directory is a git repo (no-op if already ignored per `git check-ignore`; otherwise appended to the repo-local exclude file `git rev-parse --git-path info/exclude`, not `.gitignore`, so no tracked file changes — safe for upstream clones; amended 2026-11-23 during planning). It touches nothing else in the project, never commits, and reports what it changed. Idempotent and covered by tests. Reminder printed: the first session in that project will show Claude Code's one-time approval dialog for the external import — accept it.
- **Dev profile check** (added 2026-11-23, user-approved): `agents/claude/CLAUDE.md` tells Claude that if the current project is a software development project and the dev profile is not loaded, it must say so at session start and offer to run `~/.agent-dotfiles/install.sh --enable-dev <project-dir>`; never for non-development work. Covers new projects created on an already-installed server.
- **Plan B for language rules** (deferred, tracked in its own issue): path-scoped language rules load only on first touch of a matching file. If that proves insufficient, add `--enable-dev --lang <lang>` to import per-language rules at session start. Not built now.

### 5.7 Notes for future adapters (`agents/<agent>/NOTES.md`)

Record per agent: global instruction path, import mechanism (or lack of), skills directories, config/MCP format, and these requirements:
- **opencode**: must create `~/.config/opencode/AGENTS.md` (→ neutral `AGENTS.md`) or set `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1`, otherwise it falls back to `~/.claude/CLAUDE.md` and inherits Claude-only rules. Dev profile per project via `instructions` in `opencode.json`. Verify the config schema key names against `https://opencode.ai/config.json`.
- **pi**: no imports → generate a concatenated `~/.pi/agent/AGENTS.md`; skills via `~/.agents/skills`.
- **goose**: `~/.config/goose/.goosehints` with `@` imports; MCP servers are `extensions` in `config.yaml`; serena needs a non-Claude context.
- All: check skill de-duplication before linking skills into both `~/.claude/skills` and `~/.agents/skills`; symlink support is undocumented — test.

Project-level convention (documented in README, nothing built): in shared repos, `AGENTS.md` is the main file and `CLAUDE.md` contains `@AGENTS.md`; the personal dev profile goes in the gitignored `CLAUDE.local.md` as `@~/.claude/profiles/dev.md`.

## 6. Verification before relying on undocumented behaviour

First plan tasks are spikes on this machine (results recorded in the plan/README):
1. Symlinked `~/.claude/CLAUDE.md` loads and resolves its `@~/.agent-dotfiles/...` import (check with `/memory`).
2. A `paths:` rule reached through a per-file symlink in `~/.claude/rules/` loads on Read of a matching file, and on Write of a *new* matching file.
3. `@~/.claude/profiles/dev.md` (a symlink) imported from a project `CLAUDE.local.md` shows the approval dialog once and then loads.
If a spike fails, fall back for that target to a real file generated by `install.sh` (approach 2 for that file only) and record why.

## 7. Testing

- `tests/` exercises `install.sh` with `HOME` pointed at a temp directory: fresh install, re-run idempotency (no changes, no new backups), backup of pre-existing files, settings merge preserving unrelated keys (including `autoMode`), `--dry-run` making no changes, missing-`jq` path failing loudly.
- `claude mcp` calls are tested via a stub `claude` executable on `PATH` that records its arguments.
- Test tooling choice is left to the builder; constraints: permissive license, actively maintained (Rules 13/14). Plain bash assertions are acceptable.

## 8. Cutover on this machine

1. `install.sh --dry-run`, review, then run. Live `~/.claude/CLAUDE.md` and `settings.json` are backed up (older `*.bak-doctor` backups stay where they are).
2. Dev projects currently get the dev rules from the global file; after cutover they must opt in with `install.sh --enable-dev <project-dir>`. To avoid the "silently losing dev rules" anti-goal, cutover on any machine runs `--enable-dev` for the dev projects the user names at that time. Cleaning up project instruction files is not part of cutover (issue #1).

## 8b. Repo workflow

- Host: private repo `git@github.com:sramazzina/agent-dotfiles.git` (created empty by the user, 2026-11-23).
- This repo follows the user's dev workflow (my call): initial commit on `main` with README, handoff and this spec; then one GitHub issue per plan task, a feature branch, local commits (Rule 16), one PR opened last, merged by the user.

## 9. Left to the builder

- Exact `jq` merge expression; backup directory format; summary output format.
- `servers.json` exact schema (within §5.5).
- README wording.

## 10. Open for the user

None at design time. At cutover: the list of dev projects to enable.
