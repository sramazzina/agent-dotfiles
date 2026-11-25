# Language layer loaded at session start — design (issue #2)

Date: 2026-11-25. Status: draft for approval. Size: small change (short design).

## Intent

Language rules must be in context from the start of every session in a project that uses that language. Today `rules/java.md` is a user-level path-scoped rule (`paths: ["**/*.java", "**/pom.xml"]`). Claude Code loads it only when its own Read/Write/Edit tools touch a matching file. The dev profile tells agents to work on source code through Serena's symbolic tools, not Read/Edit. An agent that follows the dev profile may therefore never load the Java rules. The user plans more languages (Python, Rust), so the mechanism must scale per language.

## Findings (probe, 2026-11-25)

Throwaway probe with `claude -p` (session env vars unset) in temp git repos:

| Case | Loaded |
|---|---|
| `CLAUDE.md` imports a file without frontmatter | yes |
| `CLAUDE.md` imports the same file with `paths: ["**/*.java"]` frontmatter | **no** |
| cardine: `CLAUDE.local.md` imports `~/.claude/profiles/dev.md` (external, approved) | yes |

So `paths:` frontmatter filters `@` imports too: importing today's `rules/java.md` would not work. Limit: probed in non-interactive mode; the implementation verifies it live in an interactive session.

## Goals

- Language rules load at session start, independent of which tools the agent uses.
- One source file per language; adding a language means adding one file.
- Per-project opt-in, alongside the dev profile.

## Non-goals

- Writing Python or Rust rules now (no empty placeholders; add each file with the first real project).
- Agents other than Claude Code.

## Anti-goals

- Two copies of the same language text to keep in sync.
- The installer touching user-owned files or links it did not create.

## Approaches

1. **Per-project import from a single source (chosen).** Language text in `languages/<lang>.md` (no frontmatter). `install.sh --enable-dev <dir> --lang <lang>` appends `@~/.agent-dotfiles/languages/<lang>.md` to the project's `CLAUDE.local.md`. The path-scoped `rules/` layer is removed. Deterministic, Serena-proof, one copy, scales by adding files. Cost: a Java project not enabled with `--lang java` gets no Java rules; acceptable because dev projects are enabled by hand anyway.
2. Per-project import plus the path-scoped rule as a safety net. Two copies (or a generation step) for little gain. Rejected.
3. Java lines folded into the dev profile under "in Maven projects". Cheapest, but loads every language's text into every dev project and does not scale to Python and Rust. Rejected after the user confirmed more languages are coming.

## Design

- **Layout:** move `rules/java.md` to `languages/java.md` and drop its frontmatter; content otherwise unchanged. Remove `rules/`. The file is neutral (no Claude-only wording), like `AGENTS.md` and `profiles/dev.md`.
- **Import target:** `@~/.agent-dotfiles/languages/<lang>.md`, directly (no symlink under `~/.claude`). `~/.agent-dotfiles` is already a symlink to the clone.
- **CLI:** `--lang <lang>` is valid only together with `--enable-dev <dir>`, repeatable (`--lang java --lang python`). Each language import line is added idempotently, with the same create/append/unchanged logic and `log` lines as the dev-profile import. `--dry-run` honoured.
- **Validation (my call):** an unknown language (no `languages/<lang>.md`) fails before any write, listing the available languages; exit 2 like other usage errors. `--lang` without `--enable-dev` is a usage error.
- **Upgrade cleanup (my call):** `link_all` removes symlinks under `~/.claude/rules/` whose target lies inside `$REPO_ROOT/rules/` and no longer exists (logs `removed:`). Anything else in `~/.claude/rules/` is untouched.
- **Docs:** README layer table and usage (`--lang`), design-spec §5.3/§5.4 note pointing here, `docs/verification.md` cutover check: in an enabled Java project, a session that has not touched any file states the Java/Maven rule. Close issue #2.
- **Tests:** `--lang java` creates/appends the import, second run unchanged, repeatable flag, unknown language fails with no write, `--lang` without `--enable-dev` fails, stale-link cleanup removes only repo-owned dangling links, existing tests that reference `rules/java.md` updated.

## Rollout (after merge)

`git pull` in `~/.agent-dotfiles`, `./install.sh` (removes the stale `~/.claude/rules/java.md` link), then `./install.sh --enable-dev <dir> --lang java` for cardine, hop-opentelemetry-plugin and data-loader-v2. Live check in one of them.

## Left to the builder

Exact placement of argument parsing and the cleanup helper in `install.sh`, test names, README wording.
