# HANDOFF — 2026-11-25 — migrating other servers (#14)

Conversation language with the user: Italian. Artifacts: English. Server `sera01.serasoft.local` is done (recorded on #14). Open items not related to other servers stay in `docs/HANDOFF-2026-11-25-migration.md`.

## What travels with git and what does not

- Travels (`git pull`): agent-dotfiles itself (layers, `languages/java.md`, `languages/bash.md`), and the trimmed `CLAUDE.md` of every project already migrated (pushed to `main`; serasoft-vscan also ships `.claude/` in `.gitignore`).
- Does not travel (machine-local): `~/.agent-dotfiles` and `~/.claude` (user-level install), and per project clone `CLAUDE.local.md`, the `.git/info/exclude` entry, and `.claude/settings.local.json`.

So every server needs the user-level install plus `--enable-dev` in each dev project clone, even for projects already migrated.

## Procedure per server

1. User-level install: follow the per-server procedure in the body of #14 (steps 1–6: clone, `install.sh --dry-run`, review, `install.sh`, re-run for idempotence, `/memory` check).
2. Ask the user for the list of projects on the server and the path where they live. Classify each one:
   - **A — already migrated, dev** (table below): `git pull` on `main` (check branch and unpushed commits first), then `install.sh --enable-dev <dir> --lang …` with the flags from the table, after a `--dry-run`. No CLAUDE.md analysis.
   - **B — already migrated, non-dev** (table below): `git pull` only, no install.
   - **C — not migrated yet** (exists only on that server or not listed): full procedure from `docs/HANDOFF-2026-11-25-migration.md` (inspect, dev or not, CLAUDE.md analysis and trim, approval).
3. For every project in A, B and C: inspect `.claude/settings.local.json` (secrets: report location and kind only, never values) and check whether `.claude/` is tracked by mistake. Propose removal or pruning; act on approval.
4. Record the server on #14 as a comment: host, date, user-level install result, projects per group with their `--lang`, non-dev projects left without the dev profile by choice.
5. Close #14 only after the last server.

## Projects already migrated (from sera01)

| Project | Group | Install flags | Notes for other servers |
|---|---|---|---|
| cardine | A | `--lang java` | |
| data-loader-v2 | A | `--lang java` | sera01 copy of `.claude/settings.local.json` held a hard-coded API key; check the local copy too |
| hop-opentelemetry-plugin | A | `--lang java` | development paused |
| hop-sqlserver-bulk-loader | A | `--lang java` | |
| hop-parquet-plugin-enhanced | A | `--lang java` | development paused |
| hop-process-template-plugins | A | `--lang java` | |
| serasoft-vscan | A | `--lang bash` | tracked `.claude/settings.local.json` was removed from the repo: a local copy with uncommitted changes blocks the pull until moved away |
| coster-hop-plugins | A | `--lang java` | lives under `work/customers/Coster/`, not `work/serasoft/`; a local untracked `.claude/` is now ignored by `.gitignore` |
| clickup-to-odoo | B | none | on sera01, 29 commits were not pushed (the user pushes). If they are still unpushed, the trimmed CLAUDE.md is not on the remote yet: ask the user before pulling |
| openmetadata-demo | B | none | |
| iceberg-platform-poc | B | none | lives under `work/sramazzina/`; GitHub repo renamed `iceberg-platform-lab` (old URL redirects) |

A project that combines languages passes one `--lang` per language (e.g. `--lang java --lang bash`). A new language gets its `languages/<lang>.md` (issue + PR) only with its first real project.

## Optional

If group A is long on a server, the install step can be a shell loop over the table rows (deterministic, Rule 5). Not worth a dedicated script for a handful of projects.
