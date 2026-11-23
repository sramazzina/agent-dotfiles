# agent-dotfiles Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the layered, agent-neutral rule files, the shared skill and MCP manifest, and a tested `install.sh` that wires them into Claude Code on a Linux server.

**Architecture:** Neutral content (`AGENTS.md`, `profiles/dev.md`, `rules/`, `skills/`, `mcp/servers.json`) at the repo root; Claude-only entries and settings under `agents/claude/`. A single bash `install.sh` creates symlinks (with backups), deep-merges a settings fragment with `jq`, registers MCP servers with `claude mcp add`, and offers `--enable-dev <dir>`. Tests run `install.sh` as a black box against a temporary `HOME` with stubbed executables.

**Tech Stack:** bash 5, coreutils, `jq` 1.7, git, Claude Code CLI 2.1.330. Tests: plain bash (no third-party test framework; `shellcheck`/`bats` are not used — not installed, and shellcheck is GPL-3, Rule 14).

**Spec:** `docs/superpowers/specs/2026-11-23-agent-dotfiles-design.md` — read it before any task.

## Global Constraints

- All files, comments, commit messages, branch names in English.
- Rule numbers 1–16 never change; Rule 6 stays "(retired; number reserved)".
- No secrets in the repo. Never print or copy values from `~/.claude.json` or `.credentials.json`; only key names may be inspected.
- `install.sh`: bash, `set -euo pipefail`, Linux only, idempotent, no prerequisite installation.
- Anchor path: `~/.agent-dotfiles` → repo clone. Imports use `@~/.agent-dotfiles/...`.
- Backups go to `$HOME/.agent-dotfiles-backups/<YYYYmmdd-HHMMSS>/<path relative to $HOME>`.
- `~/.claude/skills/synced` is never touched. Skills are linked into `~/.claude/skills/` only.
- Settings: enforced keys always applied; seeded keys (`model`, `effortLevel`) only when absent; `autoMode` never in the fragment; `hooks` replaced as a whole.
- Commits: no co-author trailer, no "Generated with" footer. One task = one commit on branch `feat/agent-dotfiles-core`. Do not push (Rule 16); the controller pushes once and opens one PR at the end.

### `install.sh` CLI contract (all tasks)

```
install.sh [--dry-run]                    full Claude Code install
install.sh --enable-dev <dir> [--dry-run] enable dev profile in one project
install.sh --help
```
Exit codes: `0` success · `1` a step failed or a required step was skipped (missing `jq`/`claude`, invalid settings JSON, missing secret env var for an unregistered server) · `2` usage error.

Summary lines on stdout, one per action, exactly these prefixes (tests grep them):
`linked: <target>` · `unchanged: <target>` · `backed-up: <target> -> <backup path>` · `stale: <target>` · `missing: <tool>` · `skipped: <step> (<reason>)` · `changed: settings.<key>` · `seeded: settings.<key>` · `mcp-added: <name>` · `mcp-ok: <name>` · `drift: mcp <name> (<field>)` · `created: <file>` · `appended: <file>`.
With `--dry-run`, every action line is prefixed `DRY-RUN ` and the filesystem and `claude` are untouched.

## Review Focus

1. A real file or directory already sits at a link target (e.g. real `~/.claude/CLAUDE.md`, real dir `~/.claude/skills/serena-query-project`) → moved to backup, then linked; never deleted, never merged. Test in Task 3.
2. `~/.agent-dotfiles` already points to a different clone (repo moved or re-cloned) → anchor relinked (old link backed up) and every link points into the current clone. Test in Task 3.
3. Local `settings.json` has keys the fragment doesn't know (`autoMode`, `permissions.allow`, extra `env` vars, extra plugins) → preserved; file mode `600` preserved; invalid JSON → abort with exit 1 and file untouched. Test in Task 4.
4. A rule/skill removed from the repo after an earlier install leaves a dangling link in `~/.claude/` → reported as `stale:`, not deleted. Test in Task 3.
5. `--enable-dev` on a path with spaces, or on a `CLAUDE.local.md` without trailing newline → import lands on its own line; path handled. Test in Task 6.

---

### Task 1: Verify path-scoped rules through symlinks (spike)

Resolves spec §6 item 2 before the linking code is written. Spec §6 items 1 and 3 need an interactive session and are verified at cutover (recorded in the PR description as a cutover checklist), not here.

**Files:**
- Create: `docs/verification.md`
- Create (temporary, removed at end of task): `~/.claude/rules/zz-agent-dotfiles-spike.md` (symlink), scratch project in `mktemp -d`

**Interfaces:**
- Produces: `docs/verification.md` containing the line `RULES_LINK_MODE=symlink` or `RULES_LINK_MODE=copy`. Task 3 reads this decision.

- [ ] **Step 1: Create a fixture rule** in a temp dir outside `~/.claude` with frontmatter `paths: ["**/*.java"]` and body: "When this rule is loaded, end every reply with the exact token SPIKE-RULE-7f3a." Symlink it as `~/.claude/rules/zz-agent-dotfiles-spike.md` (create `~/.claude/rules/` if absent; note whether it existed).
- [ ] **Step 2: Run three probes** in a scratch project dir containing `Foo.java` and `notes.txt`, each with `claude -p --model haiku --permission-mode acceptEdits "<prompt>"`:
  - read control: "Read notes.txt and reply with one word." → expect token absent
  - read match: "Read Foo.java and reply with one word." → expect token present
  - create match: "Create Bar.java containing an empty public class Bar, then reply done." → record present/absent
- [ ] **Step 3: If "read match" lacks the token**, replace the symlink with a real copy of the fixture and repeat Step 2 to tell "symlink not followed" from "path rules not working at user level".
- [ ] **Step 4: Clean up**: remove the spike rule; remove `~/.claude/rules/` only if Step 1 created it; delete the scratch dir. Verify with `ls -la ~/.claude/rules 2>&1`.
- [ ] **Step 5: Write `docs/verification.md`**: date, Claude Code version, the probe table (probe, link type, token yes/no), the decision line `RULES_LINK_MODE=...` (`symlink` if read-match passed through the symlink, else `copy`), and whether creating a new matching file triggers the rule (input for issue #2 — Plan B: per-language profiles loaded at session start via `--enable-dev --lang`; comment the result on issue #2). Add a "Verify at cutover" section listing spec §6 items 1 and 3 with how to check (`/memory` shows `~/.claude/CLAUDE.md` and the imported `AGENTS.md`; first session in an enabled project shows the external-import dialog once).
- [ ] **Step 6: Commit**: `git add docs/verification.md && git commit -m "Record path-scoped rule symlink verification"`

### Task 2: Split the rules into layer files and add the skill

**Files:**
- Create: `AGENTS.md`, `profiles/dev.md`, `rules/java.md`, `agents/claude/CLAUDE.md`, `agents/claude/dev.md`, `skills/serena-query-project/SKILL.md`
- Test: `tests/lib.sh`, `tests/run.sh`, `tests/test_rules.sh`

**Interfaces:**
- Produces: `tests/lib.sh` helpers used by every later test file — `setup_home` (exports `HOME` to a fresh `mktemp -d`, sets `TEST_HOME`, writes `$HOME/.claude.json` as `{}`, creates stub dir `$TEST_HOME/bin` with a `claude` stub that appends its argv to `$TEST_HOME/claude.log` and exits 0), `teardown_home`, `run_install [args...]` (runs `$REPO_ROOT/install.sh` with `PATH=$TEST_HOME/bin:$PATH` and `CONTEXT7_API_KEY=dummy` unless the caller exported `NO_CONTEXT7_KEY=1`; stores stdout+stderr in `$OUT` and exit code in `$RC`, never aborts the test), `assert_eq <expected> <actual> <msg>`, `assert_contains <haystack> <needle> <msg>`, `assert_not_contains`, `assert_symlink_to <path> <target>`, `assert_file_mode <path> <mode>`, `fail <msg>`. Each `tests/test_*.sh` defines `test_*` functions; `tests/run.sh` sources `lib.sh`, runs every `test_*` function of every `tests/test_*.sh` in a subshell, prints `PASS/FAIL <name>`, exits non-zero on any failure.
- Produces: the layer files at the paths above (Task 3 links them).

**Content rules** (source = `drafts/global-CLAUDE.md.proposed` wording; cross-check every obligation against live `~/.claude/CLAUDE.md`; if the draft dropped an obligation, re-add it in compact form; never renumber):

| File | Content |
|---|---|
| `AGENTS.md` | Header line: "Rule numbers are global across all layer files and never change; Rule 6 is retired." Rules 1, 3, 4, 5, 6 (retired heading only), 7, 10, 12 · Documentation format (incl. Mermaid/SVG, Draw.io mockups) · Language and tone · Commit hygiene: no co-author references, no "Generated with …" footer in commits/PRs |
| `profiles/dev.md` | Rules 2, 8, 9, 11, 13, 14, 16 · Sprints, issues, tests · Git and PR rules (minus commit hygiene) · "Commit work plans and design specs to git". Rule 16 step 1 uses generic wording "verify each with the project's local test suite"; the subagent sentence becomes "Applies to any delegated worker too: they commit locally and report; they never push." |
| `rules/java.md` | Frontmatter `paths: ["**/*.java", "**/pom.xml"]`. Java/Maven specifics moved out of Rule 16 and the testing section: verify with `mvn -pl <module> -am -DskipITs verify` (Surefire); Testcontainers ITs need a Docker socket and may only run on CI — that is the case where opening the PR earlier is justified. |
| `agents/claude/CLAUDE.md` | First line `@~/.agent-dotfiles/AGENTS.md` · Model routing — MANDATORY (verbatim meaning from live file) · Workflow skills: brainstorming → `superpowers:brainstorming`, plans → `superpowers:writing-plans` · Section "Dev profile check": "If the current project is a software development project and the dev profile is not loaded (Rules 2, 8, 9, 11, 13–16 are not in your context), say so to the user at the start of the session and offer to run `~/.agent-dotfiles/install.sh --enable-dev <project-dir>`. Do not raise it for non-development work." |
| `agents/claude/dev.md` | First line `@~/.agent-dotfiles/profiles/dev.md` · Rule 15 (verbatim quoted implementer block) · Plan execution always subagent-driven (`superpowers:subagent-driven-development`), never ask the execution mode · Implementer subagents dispatched via that skill follow Rule 16 · Tools: context7, Serena symbolic tools, `serena-query-project` skill for foreign codebases · Bash: never chain independent commands with `&&`/`;` |
| `skills/serena-query-project/SKILL.md` | Frontmatter `name: serena-query-project`, `description:` one line ("Use when exploring a codebase that is not the active Serena project, e.g. Apache Hop from a plugin project"). Body = live `~/.claude/CLAUDE.md` section "Using Serena `query_project` on another project", verbatim (steps 1–6 and Notes). |

- [ ] **Step 1: Write `tests/lib.sh`, `tests/run.sh` and failing `tests/test_rules.sh`** with:
  - `test_rule_numbers_unique`: across `AGENTS.md profiles/dev.md agents/claude/dev.md`, headings matching `^## Rule ([0-9]+) ` give exactly the set 1..16, each once.
  - `test_rule6_reserved`: `AGENTS.md` contains `## Rule 6 — (retired; number reserved)`.
  - `test_neutral_files_have_no_claude_terms`: `AGENTS.md profiles/dev.md rules/*.md` contain none of (case-insensitive) `opus`, `sonnet`, `superpowers`, `serena`, `context7`, `CLAUDE_CODE_`, `~/.claude`.
  - `test_claude_entries_import_existing_files`: every line matching `^@~/.agent-dotfiles/(.+)$` in `agents/claude/*.md` names a file that exists in the repo.
  - `test_java_rule_paths`: `rules/java.md` frontmatter has `paths:` containing `**/*.java` and `**/pom.xml`.
  - `test_skill_frontmatter`: `skills/serena-query-project/SKILL.md` has `name: serena-query-project` and a non-empty `description:`.
  - `test_commit_hygiene_universal`: `AGENTS.md` mentions co-author and the "Generated with" footer; `profiles/dev.md` does not.
  - `test_dev_profile_check_present`: `agents/claude/CLAUDE.md` contains a "Dev profile check" heading and the string `~/.agent-dotfiles/install.sh --enable-dev`; `AGENTS.md` and `profiles/dev.md` do not contain `--enable-dev`.
- [ ] **Step 2: Run** `bash tests/run.sh` → FAIL (files missing).
- [ ] **Step 3: Write the six content files** per the table.
- [ ] **Step 4: Run** `bash tests/run.sh` → all PASS.
- [ ] **Step 5: Obligation cross-check**: list, in the task report, each live-file obligation and the file+section where it now lives; flag any intentionally dropped (should be none).
- [ ] **Step 6: Commit**: `git add AGENTS.md profiles rules agents/claude/CLAUDE.md agents/claude/dev.md skills tests && git commit -m "Split global rules into neutral and Claude-specific layers"`

### Task 3: `install.sh` — skeleton, prerequisites, linking

**Files:**
- Create: `install.sh` (executable)
- Test: `tests/test_install_links.sh`

**Interfaces:**
- Consumes: Task 2 files; `RULES_LINK_MODE` from `docs/verification.md` (if `copy`, rules are installed as real copies — re-copied when content differs — instead of symlinks; everything else stays symlinked).
- Produces: functions later tasks extend inside `install.sh`: `log <prefix> <text>` (adds `DRY-RUN ` in dry-run), `backup_path <abs path>` (moves into the run's backup dir, prints `backed-up:`), `link_to <target> <source>` (idempotent symlink with backup), `have <tool>`; global `DRY_RUN` (0/1), `REPO_ROOT` (resolved with `cd "$(dirname "$(readlink -f "$0")")" && pwd -P`), `FAILED` (set to 1 by any failed/required-skipped step; final exit uses it). Step order in `main`: prerequisites → links → settings (Task 4) → MCP (Task 5) → summary.

- [ ] **Step 1: Write failing tests** (each uses `setup_home`, runs `"$REPO_ROOT/install.sh"` with a `PATH` stub dir prepended containing a no-op `claude` stub that logs args to `$TEST_HOME/claude.log`; `jq` real):
  - `test_fresh_install_links`: `~/.agent-dotfiles`→repo; `~/.claude/CLAUDE.md`→`agents/claude/CLAUDE.md`; `~/.claude/profiles/dev.md`→`agents/claude/dev.md`; `~/.claude/rules/java.md`→`rules/java.md` (or real copy per mode); `~/.claude/skills/serena-query-project`→`skills/serena-query-project`.
  - `test_rerun_is_noop`: second run prints only `unchanged:` for link targets and creates no new backup dir.
  - `test_existing_real_files_backed_up`: pre-create real `~/.claude/CLAUDE.md` ("old") and real dir `~/.claude/skills/serena-query-project/` → after run, links exist and backup dir holds `.claude/CLAUDE.md` with "old" and the dir.
  - `test_synced_untouched`: pre-create `~/.claude/skills/synced/x` → unchanged after run.
  - `test_anchor_moved_clone`: pre-create `~/.agent-dotfiles` → `/tmp/elsewhere` → relinked to repo, `backed-up:` printed.
  - `test_stale_link_reported`: pre-create `~/.claude/rules/gone.md` → `$REPO_ROOT/rules/gone.md` (nonexistent) → output contains `stale: $HOME/.claude/rules/gone.md`, link still present.
  - `test_dry_run_changes_nothing`: `--dry-run` on empty HOME → `find "$HOME"` lists nothing new besides what setup created; output lines start with `DRY-RUN `.
  - `test_runs_from_other_cwd`: `cd /` then invoke by absolute path → same links.
  - `test_usage_error`: `--bogus` → exit 2.
- [ ] **Step 2: Run** `bash tests/run.sh` → new tests FAIL.
- [ ] **Step 3: Implement `install.sh`**: arg parsing per CLI contract; prerequisites check prints `missing: <tool>` for each absent of `git jq claude gh serena serena-hooks uvx node npx`, plus `skipped: gh-auth (not logged in)` if `gh auth status` fails and `skipped: claude-auth (not logged in)` if `claude auth status` fails (both informational, not FAILED); linking per spec §5.4 using `link_to`; stale scan of symlinks in `~/.claude/rules/` and `~/.claude/skills/` whose target is under `$REPO_ROOT` and missing.
- [ ] **Step 4: Run** `bash tests/run.sh` → all PASS; `bash -n install.sh` clean.
- [ ] **Step 5: Commit**: `git add install.sh tests/test_install_links.sh && git commit -m "Add install.sh with prerequisite check and idempotent linking"`

### Task 4: Settings fragment merge

**Files:**
- Create: `agents/claude/settings.fragment.json`
- Modify: `install.sh` (add `merge_settings`)
- Test: `tests/test_install_settings.sh`

**Interfaces:**
- Consumes: Task 3 helpers.
- Produces: fragment format `{"enforce": {...}, "seed": {...}}`.

Fragment values: copy from live `~/.claude/settings.json` (exact values) — `enforce`: `env.CLAUDE_CODE_SUBAGENT_MODEL`, `permissions.defaultMode`, `hooks` (the four serena-hooks entries), `statusLine`, `enabledPlugins`, `extraKnownMarketplaces`, `skillOverrides`; `seed`: `model`, `effortLevel`. Nothing else.

Merge semantics: `result = (local * enforce_without_hooks) | .hooks = enforce.hooks`, then for each seed key absent in result, set it. Missing local file → start from `{}`. Write via temp file + `mv`, preserving the original mode (`600` when created new). Back up the old file only if content changes. Print `changed: settings.<top-level key>` for each enforced top-level key whose value differs from before, `seeded: settings.<key>` for each seed applied. If `jq` missing → `skipped: settings (jq missing)`, `FAILED=1`. Invalid local JSON → message, `FAILED=1`, file untouched.

- [ ] **Step 1: Write failing tests**:
  - `test_settings_created_when_absent`: no settings file → created with enforce + seed values, mode `600`.
  - `test_settings_preserves_unknown_keys`: local has `autoMode`, `permissions.allow: ["Bash(ls:*)"]`, `env.FOO=bar`, `enabledPlugins.other@x: true` → all preserved alongside enforced values.
  - `test_settings_seed_not_overwritten`: local `model: "sonnet"` → stays `sonnet`; no `seeded: settings.model`.
  - `test_settings_hooks_replaced`: local hooks with an extra `PostToolUse` → result `.hooks` equals fragment `.enforce.hooks`.
  - `test_settings_mode_preserved`: local file mode `600` → still `600`.
  - `test_settings_invalid_json`: local content `{not json` → exit 1, file byte-identical.
  - `test_settings_idempotent`: second run → no `changed:`/`seeded:` lines, no settings backup.
  - `test_settings_jq_missing`: PATH built without `jq` (stub dir with symlinks to only the needed coreutils/bash/git) → `skipped: settings (jq missing)`, exit 1, links still created.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** fragment file and `merge_settings`.
- [ ] **Step 4: Run** → all PASS.
- [ ] **Step 5: Commit**: `git add agents/claude/settings.fragment.json install.sh tests/test_install_settings.sh && git commit -m "Merge Claude settings fragment with enforced and seeded keys"`

### Task 5: MCP manifest and registration

**Files:**
- Create: `mcp/servers.json`
- Modify: `install.sh` (add `register_mcp`)
- Test: `tests/test_install_mcp.sh`

**Interfaces:**
- Consumes: Task 3 helpers.
- Produces: manifest schema
  ```json
  {"servers": [
    {"name": "context7", "transport": "http", "url": "https://mcp.context7.com/mcp",
     "headers": {"CONTEXT7_API_KEY": {"env": "CONTEXT7_API_KEY"}}},
    {"name": "serena", "transport": "stdio", "command": "serena",
     "args": ["start-mcp-server", "--project-from-cwd"],
     "agents": {"claude": {"args": ["start-mcp-server", "--context", "claude-code", "--project-from-cwd"]}}}
  ]}
  ```
  Header values are only ever env-var references; `agents.<agent>.args` replaces `args` for that agent.

Behaviour per server: read the current user-scope definition with `jq '.mcpServers[$name]' ~/.claude.json` (read-only; compare only `type`, `url`, `command`, `args`, and header **names** — never read or print header/env values).
- absent → build `claude mcp add --scope user --transport <t> <name> <url> -H "<Header>: $<ENV>"` (http) or `claude mcp add --scope user <name> -- <command> <args...>` (stdio); if a referenced env var is unset → `skipped: mcp <name> (env <VAR> unset)`, `FAILED=1`; else run it → `mcp-added: <name>`.
- present and equal → `mcp-ok: <name>`.
- present and different → `drift: mcp <name> (<field>)`; do not modify.
- `claude` or `jq` missing → `skipped: mcp (<tool> missing)`, `FAILED=1`.

- [ ] **Step 1: Write failing tests** (claude stub logs argv to `$TEST_HOME/claude.log`; tests write a fake `$HOME/.claude.json`):
  - `test_mcp_added_when_absent`: empty `.claude.json` `{}` and `CONTEXT7_API_KEY=dummy` → log has `mcp add --scope user --transport http context7 https://mcp.context7.com/mcp -H CONTEXT7_API_KEY: dummy` and `mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd`.
  - `test_mcp_ok_when_equal`: `.claude.json` with both servers matching (header name present, value `x`) → two `mcp-ok:`, no `mcp add` in log.
  - `test_mcp_drift_reported`: serena args without `--context claude-code` → `drift: mcp serena (args)`, no `mcp add serena` in log, exit 0.
  - `test_mcp_secret_missing`: absent context7, `CONTEXT7_API_KEY` unset → `skipped: mcp context7 (env CONTEXT7_API_KEY unset)`, exit 1, serena still added.
  - `test_mcp_never_prints_secrets`: `.claude.json` context7 header value `SECRET123` → output does not contain `SECRET123`.
  - `test_mcp_dry_run`: `--dry-run` → `DRY-RUN mcp-added:` lines, empty claude log.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** manifest and `register_mcp`.
- [ ] **Step 4: Run** → all PASS.
- [ ] **Step 5: Commit**: `git add mcp install.sh tests/test_install_mcp.sh && git commit -m "Register MCP servers from a neutral manifest"`

### Task 6: `--enable-dev <dir>`

**Files:**
- Modify: `install.sh` (add `enable_dev`)
- Test: `tests/test_enable_dev.sh`

**Interfaces:**
- Consumes: Task 3 CLI parsing and helpers.

Deviation from spec §5.6, flagged to the user: the ignore entry goes into the repo-local exclude file (`git -C <dir> rev-parse --git-path info/exclude`) instead of `.gitignore`, so no tracked file is modified (safe for upstream clones). Import line exactly `@~/.claude/profiles/dev.md`.

Behaviour: `<dir>` must exist (else exit 2). `CLAUDE.local.md` absent → create with the import line (`created:`); present without the line → append on its own line, adding a newline first if the file lacks a trailing one (`appended:`); present with it → `unchanged:`. If `<dir>` is a git work tree and `git check-ignore -q CLAUDE.local.md` fails → append `CLAUDE.local.md` to the exclude file (`appended:`); not a git repo → `skipped: ignore (not a git repo)`. If `~/.claude/profiles/dev.md` is missing → warning line `skipped: dev-profile-check (run install.sh first)` (not FAILED). Always finish with: "First session in this project will ask to approve the external import — accept it." Never commits. Does not run the full install.

- [ ] **Step 1: Write failing tests**:
  - `test_enable_dev_creates_file`: fresh git repo dir → `CLAUDE.local.md` content is exactly the import line + newline; exclude file contains `CLAUDE.local.md`; `git status --porcelain` empty.
  - `test_enable_dev_appends_without_trailing_newline`: existing `CLAUDE.local.md` = `local notes` (no newline) → second line is the import.
  - `test_enable_dev_idempotent`: run twice → one import line, one exclude entry, second run prints `unchanged:`.
  - `test_enable_dev_respects_existing_ignore`: `.gitignore` already lists `CLAUDE.local.md` → exclude file unchanged.
  - `test_enable_dev_not_git`: plain dir → file created, `skipped: ignore (not a git repo)`.
  - `test_enable_dev_path_with_spaces`: dir `"$TEST_HOME/my project"` → works.
  - `test_enable_dev_missing_dir`: nonexistent dir → exit 2.
  - `test_enable_dev_dry_run`: no files created.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `enable_dev`.
- [ ] **Step 4: Run** → all PASS.
- [ ] **Step 5: Commit**: `git add install.sh tests/test_enable_dev.sh && git commit -m "Add --enable-dev to opt projects into the dev profile"`

### Task 7: README and future-adapter notes

**Files:**
- Modify: `README.md`
- Create: `agents/opencode/NOTES.md`, `agents/pi/NOTES.md`, `agents/goose/NOTES.md`

- [ ] **Step 1: README**: purpose; layer table (spec §5.3); repo layout; prerequisites; install (`git clone … && ./install.sh --dry-run && ./install.sh`); `CONTEXT7_API_KEY` must be exported for first registration; enable a dev project (`install.sh --enable-dev <dir>` + approve dialog once); section "New project on an installed server" (universal rules apply automatically; run `~/.agent-dotfiles/install.sh --enable-dev .` once; Claude warns if it detects a dev project without the profile); section "Language rules" (path-scoped, load on first touch of a matching file; known limitation and Plan B → issue #2); project convention for shared repos (`AGENTS.md` main + `CLAUDE.md` with `@AGENTS.md`; personal dev profile in `CLAUDE.local.md`); editing rules = edit repo files, commit, no re-install needed (except copied rules if `RULES_LINK_MODE=copy`); what is never versioned; migration of existing projects → issue #1; running tests (`bash tests/run.sh`).
- [ ] **Step 2: Adapter notes** — each `NOTES.md` per spec §5.7 (global instruction path, import mechanism, skills dirs, config/MCP format, requirements and caveats; opencode: create `~/.config/opencode/AGENTS.md` or set `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1`, check schema at `https://opencode.ai/config.json`; pi: no imports → generated `AGENTS.md`; goose: `.goosehints` + `@`, MCP as `extensions`, serena non-Claude context; all: skill de-duplication and symlink support untested).
- [ ] **Step 3: Verify**: every relative link in `README.md` resolves (`grep -o '](\([^)]*\))'` → files exist); `bash tests/run.sh` still all PASS.
- [ ] **Step 4: Commit**: `git add README.md agents/opencode agents/pi agents/goose && git commit -m "Document install, dev profile and future agent adapters"`

---

## After all tasks (controller, not a task)

- Final whole-branch review; `bash tests/run.sh` green.
- Tick all issue checklists; push branch once; open one PR closing all task issues, with a cutover checklist in the body: `--dry-run` review, real run, spec §6 items 1 and 3 verified per `docs/verification.md`, `--enable-dev` on the dev projects the user names.
- Cutover on this machine happens only after the user merges.
