# opencode adapter notes (not implemented)

Facts from the design spec section 3, checked 2026-11-23. Re-verify before building.

- **Global instruction file:** `~/.config/opencode/AGENTS.md`. If absent, opencode falls back to `~/.claude/CLAUDE.md`.
- **Imports:** no `@` syntax; extra instruction files are listed in the `instructions` array of `opencode.json`.
- **Skills:** reads both `~/.claude/skills` and `~/.agents/skills` (Agent Skills `SKILL.md` format).
- **Config / MCP:** `opencode.json`. Verify key names against the schema at `https://opencode.ai/config.json`.

## Requirements for an adapter

- Create `~/.config/opencode/AGENTS.md` linking to the neutral `AGENTS.md`, or set `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1`. Otherwise opencode falls back to `~/.claude/CLAUDE.md` and inherits Claude-only rules (model routing, Claude workflow skills).
- Dev profile per project: add `profiles/dev.md` via `instructions` in the project's `opencode.json`.
- MCP: translate `mcp/servers.json` (neutral) into opencode's format; apply the `agents.opencode` override block if one is added.

## Caveats

- Skill de-duplication: opencode reads both skill directories, so linking skills into both `~/.claude/skills` and `~/.agents/skills` can load duplicates. The Claude adapter links only into `~/.claude/skills`.
- Symlink support for instruction files and skills is undocumented: test it.
- License MIT, actively released (Nov 2026).
