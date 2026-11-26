# HANDOFF — 2026-11-25 — project migration (#14) progress (supersedes HANDOFF-2026-11-25-resume.md)

Conversation language with the user: Italian. Artifacts: English. Dev clone: `/home/sramazzina/work/sramazzina/agent-dotfiles` (the older handoff named a wrong path under `work/serasoft/`). Installed clone: `~/.agent-dotfiles` (on `main`; may lag the dev clone by docs-only commits — `git -C ~/.agent-dotfiles pull` when convenient). All projects live under `/home/sramazzina/work/serasoft/`.

## Migration procedure (#14), as refined today

Per project, one at a time, the user names it:

1. Inspect: branch, unpushed commits, tracked `.claude/` files, secrets in tracked files or `.claude/settings.local.json` (report location/kind only, never values).
2. Ask the user whether the project is a development project. Dev → dry-run `install.sh --enable-dev <dir> [--lang <lang>]` (one `--lang` per language with a file in `languages/`; `java` and `bash` exist; a multi-language project passes several, e.g. `--lang java --lang bash`). Non-dev → no install.
3. Analyse `CLAUDE.md` against the layers (Sonnet subagent for long files) and trim it to non-derivable guidance (criterion recorded on #14): remove versions/trees/standard commands/architecture restating code/layer duplicates/precedence claims/heavy emphasis; keep pointer line (dev projects), purpose, non-standard build needs, deliberate choices with reasons, invariants, conventions, project policies. Source: https://code.claude.com/docs/en/memory and https://code.claude.com/docs/en/best-practices (neither user nor project instructions override each other; target < 200 lines; plain wording over IMPORTANT/MUST).
4. Propose, act on approval. `CLAUDE.md` and handoffs go directly on `main`. Push only when the user asks.

## Projects done

| Project | Type | Install | Notes |
|---|---|---|---|
| cardine | dev, Java | `--lang java` (earlier) | CLAUDE.md already minimal (Rules 17–19 + header) |
| data-loader-v2 | dev, Java | `--lang java` (earlier) | CLAUDE.md 162 → 66, pushed |
| hop-opentelemetry-plugin | dev, Java, development paused (Hop parent intentionally behind) | `--lang java` (earlier) | CLAUDE.md 137 → 76, pushed |
| hop-sqlserver-bulk-loader | dev, Java | `--lang java` today | CLAUDE.md trimmed, release doc fixed (patch by default, minor when planned, CHANGELOG decides), pushed |
| hop-parquet-plugin-enhanced | dev, Java, development paused | `--lang java` today | CLAUDE.md 95 → 35, tracked memory files removed, project `docs/HANDOFF-2026-11-25-resume.md` lists release inconsistencies; pushed. Local branch `fix/39-propagate-previous-fields` unpushed (user's WIP) |
| hop-process-template-plugins | dev, Java | `--lang java` today | CLAUDE.md 160 → 45 (commit `394f04b` on `main`, pushed after rebase on 6 new remote commits). Untracked `.claude/` removed (held an expired hard-coded GitHub token). Tracked `.serena/memories/*.md` overlap the removed content (left as is); `.serena/project.yml` has an unrelated uncommitted Serena regeneration |
| serasoft-vscan | dev, Bash | `--lang bash` today | CLAUDE.md 90 → 39 (`fdde61d`, `4992191`, pushed). Tracked `.claude/settings.local.json` removed and `.claude/` ignored. Stale `tests/run.sh` description and nonexistent Markdown report fixed. Untracked `targets/hop-*.yaml` and `.serena/` are the user's, left as is |
| coster-hop-plugins (`/home/sramazzina/work/customers/Coster/`) | dev, Java, customer project | `--lang java` 2026-11-26 | CLAUDE.md 87 → 28 (`4e0f980` on `main`). Untracked `.claude/` removed and ignored. JDK 11 fixed (Coster runtime). `Encrypted` passwords in `integration/metadata/rdbms/*.json` are dev passwords (user: not a concern). README/pom/adoc leftovers in SeraSoft/coster-hop-plugins#53, left to the project agent |
| iceberg-platform-lab (`/home/sramazzina/work/sramazzina/`; renamed from `iceberg-platform-poc` on 2026-11-26: directory, GitHub repo, remote URL, `~/.claude/projects` dir, Serena config; Compose stack stopped before the rename) | non-dev (lab platform) | none, by choice | CLAUDE.md 19 → 13 (`727b51a`, pushed): all previous content duplicated the layers; now purpose, git workflow (lab changes via branch + PR, docs direct to `main`, confirmed by the user) and the `NOTES.md` `Dnn`/`Fnn` convention |
| clickup-to-odoo | non-dev (Hop flow files) | none, by choice | CLAUDE.md trimmed; project keeps a temporary override: no issues, no branches, no PRs, commit on `main`. 29 local commits NOT pushed (user pushes). Odoo-write hook item recorded in its `docs/HANDOFF-2026-10-31.md` |
| openmetadata-demo | non-dev (demo environment) | none, by choice | CLAUDE.md 66 → 12 with an explicit git workflow (environment changes via branch + PR; docs/runbooks/slides/handoff direct to `main` — inferred from history, user to confirm); pushed |

## Open items (the user picks; do not start on your own)

1. **#14 migration** — continue with the next project the user names.
2. **#29** — company-wide changelog/versioning/release strategy for company projects (cardine, data-loader-v2). Hop plugins are out of scope (they follow upstream). Comment on #29 proposes "the CHANGELOG content decides the bump".
3. **#30** — reduce emphasis (MANDATORY/NEVER/ALWAYS) in layers and project CLAUDE.md files; move never-bend rules to hooks/permissions.
4. **Unification list** → issue + PR into `profiles/dev.md`: strict merge guard (`merged` literal answer); `git pull` of `main` at task start. Then trim cardine Rule 19.
5. **Permissions phase 2**: prune per-project `.claude/settings.local.json` (data-loader-v2 holds a hard-coded API key in a curl entry — security-relevant; hop-sqlserver-bulk-loader has one-off entries, a broad `Bash(git push *)` allow overlapping the push policy, old `mcp__plugin_serena_serena__*` names, stale `scheduled_tasks.lock`).
6. **Close #14** at the end: comment with server, date, enabled projects, and the non-dev projects left without the dev profile by choice (clickup-to-odoo, openmetadata-demo).
7. **Language files**: add `languages/<lang>.md` only with the first real project in that language (no placeholders). Done for Bash (#31, PR #32, with serasoft-vscan).
8. **Deferred minors** (unchanged from the previous handoff): guard `mvn -pl deploy verify` false ask; `docker -H x push` not caught; README `gh api` bullet lacks `--method`; push-policy and lang-import parked minors (dry run logs `created:` twice for `CLAUDE.local.md`).
9. Interactive live check of `--lang` (verification item 11) still open.
