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
| create match (new `Bar.java`), first run in a dir already holding `Foo.java` (confounded: no tool trace) | symlink | yes |
| create match, re-run in a fresh dir with only `notes.txt`, stream-json tool trace, run 1 | symlink | yes (only tool call: `Write`) |
| create match, same re-run, run 2 | symlink | yes (only tool call: `Write`) |

Step 3 (retry with a real copy) was not needed: the read-match probe passed through the symlink.

RULES_LINK_MODE=symlink

### Creation trigger (input for issue #2)

The first create probe was confounded (the dir already contained `Foo.java`, no tool trace). It was re-run twice in a fresh dir containing only `notes.txt`, with `--output-format stream-json --verbose`. In both runs the only tool call was `Write` of `Bar.java` (no Read/Glob/Bash of any .java file), and the reply ended with `SPIKE-RULE-7f3a`. Conclusion: creating a new file matching the `paths` glob triggers the rule, so Plan B is not required for the create case.

Caveats: haiku model only, and only a small number of runs (read-match: 1 run; create: 2 clean runs plus the confounded one).

## Verify at cutover

These need an interactive session and are checked when switching over (spec section 6, items 1 and 3):

1. `/memory` lists `~/.claude/CLAUDE.md` and the imported `AGENTS.md`.
2. The first session in an enabled project shows the external-import dialog once (and not again afterwards).
