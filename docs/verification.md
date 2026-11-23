# Verification

## Path-scoped rules through symlinks (spec section 6, item 2)

- Date: 2026-11-23
- Claude Code version: 2.1.330
- Fixture: user-level rule `~/.claude/rules/zz-agent-dotfiles-spike.md` (symlink to a file outside `~/.claude`), frontmatter `paths: ["**/*.java"]`, body asking to end every reply with `SPIKE-RULE-7f3a`.
- Command: `claude -p --model haiku --permission-mode acceptEdits "<prompt>"` from a scratch project containing `Foo.java` and `notes.txt`.

| Probe | Link type | Token present |
|-------|-----------|---------------|
| read control (`notes.txt`) | symlink | no |
| read match (`Foo.java`) | symlink | yes |
| create match (new `Bar.java`) | symlink | yes |

Step 3 (retry with a real copy) was not needed: the read-match probe passed through the symlink.

RULES_LINK_MODE=symlink

### Creation trigger (input for issue #2)

Creating a new file matching the `paths` glob did trigger the rule (token present in the reply after the create). Plan B (per-language profiles loaded at session start via `--enable-dev --lang`) is therefore not required for the create case. Caveat: single run, haiku model.

## Verify at cutover

These need an interactive session and are checked when switching over (spec section 6, items 1 and 3):

1. `/memory` lists `~/.claude/CLAUDE.md` and the imported `AGENTS.md`.
2. The first session in an enabled project shows the external-import dialog once (and not again afterwards).
