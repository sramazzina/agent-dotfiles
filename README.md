# agent-dotfiles

Personal, versioned configuration for coding agents: behavioral rules, skills and MCP server definitions. Cloned on every Linux server where agents run and wired into each agent's home configuration by `install.sh`.

Only Claude Code is wired today. The content is organised agent-neutrally so opencode, pi or goose can be added later (see `agents/*/NOTES.md`).

- Design: [`docs/superpowers/specs/2026-11-23-agent-dotfiles-design.md`](docs/superpowers/specs/2026-11-23-agent-dotfiles-design.md)
- Bootstrap handoff: [`HANDOFF-2026-11-23-bootstrap.md`](HANDOFF-2026-11-23-bootstrap.md)
- Verification results: [`docs/verification.md`](docs/verification.md)

## Rule layers

Rule numbers are global across all layer files, never renumbered; Rule 6 is retired.

| | Neutral | Claude-only |
|---|---|---|
| **Universal** (always on): `AGENTS.md`, `agents/claude/CLAUDE.md` | Rules 1, 3, 4, 5, 7, 10, 12; language and tone; documentation format; commit hygiene | Model routing; workflow skills (brainstorming, writing-plans) |
| **Development** (per-project opt-in): `profiles/dev.md`, `agents/claude/dev.md` | Rules 2, 8, 9, 11, 13, 14, 16; sprints, issues, tests; git and PR rules | Rule 15; subagent-driven plan execution; tools section (context7, Serena); Bash chaining rule |
| **Language**: `languages/<lang>.md` | Rule content, imported per project via `--enable-dev <dir> --lang <lang>` | None |

## Repo layout

```
AGENTS.md              neutral universal rules
profiles/dev.md        neutral development rules
languages/java.md      language rules (imported per project)
skills/                skills (serena-query-project)
mcp/servers.json       neutral MCP manifest (secrets referenced by env-var name only)
agents/claude/         Claude entry files + settings.fragment.json
agents/{opencode,pi,goose}/NOTES.md   notes for future adapters
install.sh             Claude Code installer
tests/                 installer tests
docs/                  spec, plan, verification
```

## Prerequisites

`install.sh` never installs anything. Required: `jq` and `claude` (without them the settings and MCP steps are skipped and the run exits 1). Also checked and reported when missing: `git`, `gh`, `serena`, `serena-hooks`, `uvx`, `node`, `npx`. `claude` and `gh` should be logged in.

## Install

```bash
git clone git@github.com:sramazzina/agent-dotfiles.git ~/.agent-dotfiles   # private repo; any location works
cd ~/.agent-dotfiles
export CONTEXT7_API_KEY=...        # needed only for the first context7 registration on a server
./install.sh --dry-run             # review
./install.sh
```

The installer is idempotent: re-running with nothing to change prints `unchanged:` lines and creates no backup. What it does:

- Creates the anchor `~/.agent-dotfiles` (symlink to the clone; if the clone is already there it is left as-is). All imports use this anchor.
- Symlinks `~/.claude/CLAUDE.md`, `~/.claude/profiles/dev.md`, and each skill into `~/.claude/skills/`. `~/.claude/skills/synced` is never touched.
- Merges `agents/claude/settings.fragment.json` into `~/.claude/settings.json` (a real, local file; a symlinked one is written through to its target). Enforced keys always win (`hooks` is replaced as a whole); seeded keys (`model`, `effortLevel`) are written only when absent. `autoMode` and any other local key are preserved.
- Registers the MCP servers in `mcp/servers.json` at user scope via `claude mcp add`. An existing server with a different definition is reported as drift and never overwritten.
- Backs up anything it replaces to `~/.agent-dotfiles-backups/<YYYYmmdd-HHMMSS>[-N]/` (path preserved relative to `$HOME`). The directory is created only when something is backed up.

### Summary lines and exit codes

Every action prints one line; in `--dry-run` each line is prefixed `DRY-RUN ` and nothing is changed.

| Prefix | Meaning |
|---|---|
| `linked:` / `unchanged:` | symlink created / already correct; `unchanged:` also covers settings and ignore entries |
| `created:` / `appended:` | `--enable-dev`: `CLAUDE.local.md` created / import (or git exclude entry) appended |
| `backed-up:` | existing file moved (or, for settings.json, copied) to the backup dir |
| `changed: settings.<key>` / `seeded: settings.<key>` | enforced key changed / seeded key added |
| `mcp-added:` / `mcp-ok:` / `drift:` | server registered / matches manifest / differs (left alone) |
| `missing:` | prerequisite not found |
| `stale:` | link into this clone whose source is gone (reported, never deleted) |
| `skipped: <what>` | step not attempted (e.g. `skipped: mcp context7 (env CONTEXT7_API_KEY unset)`); `--enable-dev` may print `skipped: ignore (not a git repo)` and `skipped: dev-profile-check (run install.sh first)` |
| `failed: <what>` | hard failure (e.g. `failed: link <target>`, `failed: mcp (invalid manifest)`) |

Exit codes: `0` ok; `1` a `failed:` line, a missing `jq`/`claude`, or a skipped MCP/settings step; `2` usage error (including `--enable-dev` with a missing or empty directory argument).

### MCP and secrets

`CONTEXT7_API_KEY` must be exported for the first registration on a server; the manifest references it by name only. Caveat: the value is passed to `claude mcp add -H` on the command line, so it is briefly visible in the process list (a CLI limitation); the installer never prints it. Servers already registered are only compared, never rewritten, so later runs do not need the variable.

## Enable the dev profile in a project

The universal rules apply everywhere automatically. The development layer is opt-in per project:

```bash
~/.agent-dotfiles/install.sh --enable-dev /path/to/project [--lang <lang>]...    # --dry-run supported
```

This adds the line `@~/.claude/profiles/dev.md` to `<project>/CLAUDE.local.md` (created if absent, no-op if present) and, in a git repo, adds `CLAUDE.local.md` to the repo-local `.git/info/exclude` (not `.gitignore`, so no tracked file changes; skipped if already ignored). Each `--lang <lang>` (repeatable) then appends `@~/.agent-dotfiles/languages/<lang>.md` after the dev import, once per language. An unknown language name prints `unknown language: <name>` and `available: ...`, exits 2 and writes nothing. `--lang` without `--enable-dev` is a usage error. It never commits. The first Claude session in the project shows a one-time external-import approval dialog: accept it (declining disables the import permanently for that project).

### New project on an installed server

Universal rules apply with no action. Run `~/.agent-dotfiles/install.sh --enable-dev . --lang <lang>` once in the project. If Claude detects a software project without the dev profile loaded, it says so at session start and offers to run that command, with `--lang` for each language that has a file in `languages/` (never for non-development work).

## Irreversible-operations guard

Some commands cannot be undone once they run. The installer sets rules and a hook so that Claude Code never runs them without you. This applies in the main session and in subagents, whatever a project allows.

Refused (`deny`):
- `gh repo delete`
- force push to `main` or `master`

Prompt every time (`ask`):
- `gh pr merge`
- `gh release create | edit | delete | upload`
- `mvn deploy`, `./mvnw deploy`, `docker push`
- `gh workflow run`, `gh secret set | delete | remove`, `gh variable set | delete`
- `gh api` calls that change data (`-X` other than `GET`, or any `-f`, `-F`, `--field`, `--raw-field`, `--input`)

Push policy (spec `docs/superpowers/specs/2026-11-24-push-policy-design.md`):
- A push to a feature branch is free. A docs-only push to `main` is free (only `README.md`, `CLAUDE.md`, `CHANGELOG.md` or `docs/HANDOFF*.md` change, on a remote other than `upstream`).
- Any other push to `main`, `master` or the remote `upstream` needs your explicit request in auto mode. In other modes it prompts.
- A force push to `main` or `master`, and deleting them, are denied.
- In auto mode the hook gives no decision for protected pushes. The auto-mode classifier decides, using the `soft_deny` entry in the fragment's `autoMode` block.
- The fragment sets `classifyAllShell: true`. Project `allow` lists no longer skip the classifier in auto mode.

The full policy is in section 4 of `docs/superpowers/specs/2026-11-24-irreversible-ops-guard-design.md`.

The rules live in `agents/claude/settings.fragment.json` and show in `/permissions`. The hook `hooks/guard-irreversible.sh` is the backstop. It also catches variants the rules miss, such as `git -C . push origin main`, `/usr/bin/git push origin main`, `bash -c '...'`, env-var prefixes and compound commands. The hook only adds friction. It never allows a command.

To run a refused command yourself, type it in the session with the `!` prefix, for example `! gh repo delete owner/name`.

Caveats:
- This guards against an agent's mistakes. It is not a security boundary and does not stop deliberate evasion.
- `install.sh` merges `permissions.deny`, `ask` and `allow` as a union with your own entries. If a later version of the policy drops a rule, the old entry stays in `~/.claude/settings.json`. Remove it by hand. `autoMode.soft_deny` (and `allow`, `hard_deny`, `environment` if the fragment defines them) merge the same way.
- Manual upgrade step 1: remove the old `Bash(git push *)` entry from `permissions.ask` in `~/.claude/settings.json` (spec section 5.2).
- Manual upgrade step 2: review the stale `autoMode` block left by an earlier manual setup and remove it with your approval (spec section 5.4).

## Language rules

`languages/<lang>.md` hold the language rules (no frontmatter, neutral wording). A project imports them at session start: `--enable-dev <dir> --lang <lang>` appends `@~/.agent-dotfiles/languages/<lang>.md` to its `CLAUDE.local.md`, after the dev import.

Why an import and not path-scoped rules: a path-scoped rule loads only when Claude reads, writes or edits a matching file, and the dev profile routes code access through Serena. The guidance would be absent at the start of the session. This closes issue #2 (closed by this change).

To add a language, add one file `languages/<lang>.md` with no frontmatter and neutral wording. The name must match `^[A-Za-z0-9_-]+$`. No installer change is needed.

Upgrade from the old layout: `install.sh` no longer links `rules/`, and never deletes links. A leftover `~/.claude/rules/java.md` is reported as `stale:`. Remove it by hand, then re-run `--enable-dev <dir> --lang java` for each Java project.

## Project convention for shared repos

`AGENTS.md` is the main project file; `CLAUDE.md` contains just `@AGENTS.md`. The personal dev profile goes in the git-excluded `CLAUDE.local.md` (via `--enable-dev`), never in shared files.

## Editing rules

Edit the files in this repo and commit. Symlinks mean changes are live without re-running `install.sh`. Re-run it only after adding new skill files (new links) or changing `settings.fragment.json` or `mcp/servers.json`. New language files need no re-run: projects import them by path.

## Never versioned

`~/.claude.json` (MCP registrations live there; secrets included), `~/.claude/settings.json` (local file with local keys such as `autoMode`), `CLAUDE.local.md` files, API keys, and `~/.agent-dotfiles-backups/`.

## Migration of existing projects

Cleaning up per-project instruction files that duplicate these rules is not part of the install: see issue #1.

## Tests

```bash
bash tests/run.sh
```

Runs the installer against a temporary `HOME` with a stub `claude`; no real configuration is touched.
