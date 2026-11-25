# HANDOFF — 2026-11-25 — resume point (supersedes HANDOFF-2026-11-24-push-policy.md)

Conversation language with the user: Italian. Artifacts: English. Dev clone: `/home/sramazzina/work/serasoft/agent-dotfiles` (on `main`, clean). Installed clone: `~/.agent-dotfiles` (on `main`, `ee807d1`).

## Shipped and cut over on this machine (2026-11-24/25)

- **#22** irreversible-operations guard (earlier).
- **#27** push policy (issues #23, #24): feature-branch and docs-only pushes free; pushes to `main`/`master`/`upstream` need an explicit request (auto mode) or a prompt (default mode); force push / deletion of main denied. Cutover done: `Bash(git push *)` removed from `permissions.ask`; stale iceberg `autoMode` block removed with the user's approval. Live checks passed: 4, 8, 9. Still to run in a fresh session: 5 (subagent push to main), 6 (auto mode feature push free), 7 (auto mode unrequested push to main blocked), 10 (docs-only push to main free).
- **#26** global rule: ask the user before escalating to a more capable model. Standing approval: SDD final whole-branch review on Opus (auto-memory `final-review-most-capable-model`).
- **#28** language rules at session start (issue #2): `languages/java.md`, imported per project with `install.sh --enable-dev <dir> --lang java`. Cutover done: stale `~/.claude/rules/java.md` removed; `--lang java` applied to cardine, hop-opentelemetry-plugin, data-loader-v2 (each `CLAUDE.local.md` now imports `@~/.claude/profiles/dev.md` and `@~/.agent-dotfiles/languages/java.md`). Automated probe in cardine (`claude -p`, no tools) quoted the Java/Maven verify command. Interactive live check (verification item 11) still open.

## Open items (the user picks; do not start on your own)

1. **#14 migration** — next project on this machine. The user gives projects one at a time. Per project: dry-run `install.sh --enable-dev <dir> [--lang <lang>]`, analyse its CLAUDE.md vs the layers (Sonnet subagent), propose, act on approval.
2. **Unification list** → one issue + PR into `profiles/dev.md`: strict merge guard (post-merge cleanup only on the literal answer `merged`; never infer a merge); `git pull` of `main` at the start of each task. Then trim cardine Rule 19.
3. **Permissions phase 2**: prune per-project `.claude/settings.local.json` (data-loader-v2 holds a hard-coded API key in a curl entry — security-relevant); shared Java allow list (less valuable now that `classifyAllShell` is on).
4. **Close #14**: comment with server, date, enabled projects; tick checklist.
5. **Python / Rust language files**: add `languages/python.md` / `languages/rust.md` with the first real project in that language (no placeholders).
6. **Deferred minors**: guard `mvn -pl deploy verify` false ask; `docker -H x push` not caught; README `gh api` bullet lacks `--method`; hop-opentelemetry-plugin `docs/guides/tech/release-process.md` line 53 cites `hop-parquet-plugin`; push-policy parked minors (last pipeline stage `cd` leak, forced glob/`--mirror` only ask); lang-import parked minors (`add_import` log lines do not name the import; dry run logs `created:` for every line; trailing-whitespace / CRLF duplicate append).
