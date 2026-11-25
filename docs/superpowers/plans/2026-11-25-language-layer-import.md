# Language Layer Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Load per-language rules at session start through a per-project import (`install.sh --enable-dev <dir> --lang <lang>`), replacing the path-scoped `rules/` layer.

**Architecture:** Language text moves to `languages/<lang>.md` (no frontmatter). `enable_dev` gains a repeatable `--lang` that appends `@~/.agent-dotfiles/languages/<lang>.md` to the project's `CLAUDE.local.md` with the same idempotent create/append logic as the dev-profile import. `link_all` stops linking `rules/`; the existing `scan_stale` reports the leftover link.

**Tech Stack:** bash, coreutils, git; tests in `tests/*.sh` via `bash tests/run.sh` (helpers in `tests/lib.sh`: `setup_home`, `run_install` → `$OUT`/`$RC`, `assert_eq`, `assert_contains`, `fail`).

**Spec:** `docs/superpowers/specs/2026-11-25-language-layer-import-design.md`

## Global Constraints

- Dependencies: bash, coreutils, git only (as today).
- Import line format, exact: `@~/.agent-dotfiles/languages/<lang>.md`.
- `languages/*.md` have no frontmatter and are neutral: no `opus|sonnet|superpowers|serena|context7|CLAUDE_CODE_|~/.claude` (existing neutral-file test).
- The installer never deletes user files or links; stale links into the clone are reported (`stale: <path>`), never removed.
- Usage errors exit 2 and write nothing.
- English everywhere. One commit per task, on branch `feat/lang-import`. No co-author or "Generated with" lines. Never push.
- Full suite green: `bash tests/run.sh`.

## Review Focus

1. Unknown language together with a valid one (`--lang java --lang cobol`): nothing is written, not even the dev import or the java line. Pinned in Task 1 (`test_enable_dev_lang_unknown_writes_nothing`).
2. `CLAUDE.local.md` that already has the dev import but not the language line (the three migrated projects): only the language line is appended; dev line unchanged. Pinned in Task 1 (`test_enable_dev_lang_on_already_enabled_project`).
3. The same `--lang` given twice: one import line. Pinned in Task 1 (`test_enable_dev_lang_repeated_same`).
4. Upgrade from the old layout: a leftover `~/.claude/rules/java.md` link into the clone is reported stale and kept. Pinned in Task 1 (`test_old_rules_link_reported_stale`).
5. `--dry-run` with `--lang`: logs the lines, writes nothing. Pinned in Task 1 (`test_enable_dev_lang_dry_run`).

---

### Task 1: Language layout and `--lang`

**Files:**
- Move: `rules/java.md` → `languages/java.md` (`git mv`), then drop its frontmatter (lines 1-3); body unchanged.
- Modify: `install.sh` (`usage`, `main` argument parsing, `enable_dev`, `link_all`)
- Test: `tests/test_enable_dev.sh`, `tests/test_install_links.sh`, `tests/test_rules.sh`

**Interfaces:**
- Produces: `LANGS` (bash array of language names from `--lang`, in order); `add_import <file> <line>` — appends `<line>` to `<file>` with the existing create/append/unchanged logic and log lines (`created:`, `appended:`, `unchanged:`, `failed:`); `enable_dev <dir>` calls it for the dev import, then for each language.
- Consumed by Task 2 (docs): CLI `install.sh --enable-dev <dir> [--lang <lang>]... [--dry-run]`.

- [ ] **Step 1: Write the failing tests** in `tests/test_enable_dev.sh` (define `LANG_JAVA='@~/.agent-dotfiles/languages/java.md'`):
  - `test_enable_dev_lang_creates_both_lines`: new repo, `--enable-dev proj --lang java` → RC 0; file is exactly two lines: `$IMPORT` then `$LANG_JAVA`.
  - `test_enable_dev_lang_on_already_enabled_project`: file already holds `$IMPORT`; run with `--lang java` → line 1 `$IMPORT`, line 2 `$LANG_JAVA`, 2 lines total; `$OUT` contains `unchanged:` and `appended:`.
  - `test_enable_dev_lang_idempotent`: run twice → 2 lines; second `$OUT` has no `appended:` and no `created:`.
  - `test_enable_dev_lang_repeated_same`: `--lang java --lang java` → `$LANG_JAVA` appears once.
  - `test_enable_dev_lang_unknown_writes_nothing`: `--lang java --lang cobol` → RC 2; `CLAUDE.local.md` does not exist; `.git/info/exclude` has no `CLAUDE.local.md`; `$OUT` contains `unknown language: cobol` and `available: java`.
  - `test_lang_without_enable_dev_is_usage_error`: `run_install --lang java` → RC 2; `$OUT` contains `Usage:`; no `~/.claude/CLAUDE.md` link created.
  - `test_enable_dev_lang_missing_value`: `--enable-dev proj --lang` → RC 2.
  - `test_enable_dev_lang_dry_run`: `--dry-run --enable-dev proj --lang java` → no `CLAUDE.local.md`; `$OUT` contains `DRY-RUN created:`.
  In `tests/test_install_links.sh`:
  - `test_fresh_install_links`: replace the `rules/java.md` symlink assertion with `[ ! -e "$HOME/.claude/rules/java.md" ] || fail "rules layer still linked"`.
  - `test_old_rules_link_reported_stale`: pre-create `ln -s "$REPO_ROOT/rules/java.md" "$HOME/.claude/rules/java.md"` (dangling after the move); `run_install` → `$OUT` contains `stale: $HOME/.claude/rules/java.md`; the link still exists (`[ -L ... ]`).
  - `test_clone_at_anchor_location`: copy `languages` instead of `rules`; replace the `rule link dangles` check with `[ -f "$HOME/.agent-dotfiles/languages/java.md" ] || fail "language file missing"`.
  In `tests/test_rules.sh`:
  - `NEUTRAL="AGENTS.md profiles/dev.md languages/*.md"`.
  - Replace `test_java_rule_paths` with `test_language_files_have_no_frontmatter`: for each `languages/*.md`, line 1 is not `---`; and `languages/java.md` contains `mvn -pl <module> -am -DskipITs verify`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh 2>&1 | grep -E '^FAIL'`
Expected: the new/changed tests above FAIL; nothing else fails.

- [ ] **Step 3: Move the language file**

`git mv rules/java.md languages/java.md`, delete the 3 frontmatter lines, keep the body byte-identical. `rules/` no longer exists.

- [ ] **Step 4: Implement in `install.sh`**
  - `usage`: add the line `  install.sh --enable-dev <dir> [--lang <lang>]... [--dry-run]` (replacing the current `--enable-dev` line).
  - `main`: `--lang` requires a non-empty value (else usage, exit 2) and appends to `LANGS`; after parsing, `LANGS` non-empty with `ENABLE_DEV_DIR` empty → usage, exit 2.
  - Validation happens in `enable_dev` before any write (after the directory check): each language must have `$REPO_ROOT/languages/<lang>.md`; otherwise print `unknown language: <lang>` and `available: <space-separated names>` to stderr and exit 2. Duplicates are skipped silently.
  - Extract the existing create/append/unchanged block into `add_import <file> <line>` and call it for `@~/.claude/profiles/dev.md`, then for `@~/.agent-dotfiles/languages/<lang>.md` per language. The exclude and reminder logic run once, unchanged.
  - `link_all`: remove the `rules/*.md` loop and its comment. `scan_stale` stays as is.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: 0 FAIL.

- [ ] **Step 6: Commit**

```bash
git add -A languages rules install.sh tests/test_enable_dev.sh tests/test_install_links.sh tests/test_rules.sh
git commit -m "feat(install): --lang imports per-language rules at session start; drop path-scoped rules layer (#2)"
```

### Task 2: Docs and the dev-profile offer

**Files:**
- Modify: `README.md` (layer table line 19, tree line 26, install bullet line 53, "Enable the dev profile" section around lines 82-92, "Language rules" section lines 128-130, "Editing rules" line 138)
- Modify: `agents/claude/CLAUDE.md` (section `# Dev profile check`)
- Modify: `docs/verification.md` ("Verify at cutover" list)
- Modify: `docs/superpowers/specs/2026-11-23-agent-dotfiles-design.md` (§5.3 language row and bullet, §5.4 `~/.claude/rules` row: one line each pointing to the 2026-11-25 spec as superseding)
- Test: `tests/test_rules.sh`

**Interfaces:**
- Consumes: Task 1's CLI and import line format.

- [ ] **Step 1: Write the failing test** in `tests/test_rules.sh`:
  - `test_dev_profile_check_mentions_lang`: the body of `# Dev profile check` in `agents/claude/CLAUDE.md` contains `--lang`.
  - `test_readme_has_no_path_scoped_language_layer`: `README.md` does not contain `paths:` auto-activation and does contain `--lang`.

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/run.sh 2>&1 | grep -E 'dev_profile_check_mentions_lang|readme_has_no_path_scoped|^FAIL'`
Expected: both FAIL.

- [ ] **Step 3: Edit the docs**
  - `agents/claude/CLAUDE.md` Dev profile check: the offered command becomes `~/.agent-dotfiles/install.sh --enable-dev <project-dir> --lang <lang>` for each language of the project that has a file in `~/.agent-dotfiles/languages/`; also say so when the dev profile is loaded but a language import for the project's language is missing.
  - README: language layer row = `languages/<lang>.md`, imported per project via `--enable-dev <dir> --lang <lang>`; tree line `languages/java.md  language rules (imported per project)`; install bullet no longer mentions `rules/*.md`; "Language rules" section explains the session-start import, why (path-scoped rules load only on Read/Write/Edit, and the dev profile routes code access through Serena), how to add a language (one file, no frontmatter, neutral wording), and the upgrade step: remove the `stale:` link `~/.claude/rules/java.md` by hand, then re-run `--enable-dev <dir> --lang java` per Java project. Issue #2 reference updated to "closed by this change".
  - `docs/verification.md`: add to "Verify at cutover": "In a project enabled with `--lang java`, a new session that has not touched any file states the Java/Maven rule (`mvn -pl <module> -am -DskipITs verify`)."

- [ ] **Step 4: Run the full suite**

Run: `bash tests/run.sh`
Expected: 0 FAIL.

- [ ] **Step 5: Commit**

```bash
git add README.md agents/claude/CLAUDE.md docs/verification.md docs/superpowers/specs/2026-11-23-agent-dotfiles-design.md tests/test_rules.sh
git commit -m "docs: language layer via per-project import; dev profile check offers --lang (#2)"
```
