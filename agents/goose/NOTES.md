# goose adapter notes (not implemented)

Facts from the design spec section 3, checked 2026-11-23. Re-verify before building.

- **Global instruction file:** `~/.config/goose/.goosehints`.
- **Imports:** `@file` syntax inside `.goosehints`.
- **Skills:** reads both `~/.claude/skills` and `~/.agents/skills` (Agent Skills `SKILL.md` format).
- **Config / MCP:** `config.yaml`; MCP servers are `extensions` entries.

## Requirements for an adapter

- Write `~/.config/goose/.goosehints` importing the neutral `AGENTS.md` via `@~/.agent-dotfiles/AGENTS.md` (check that `@~` expansion works).
- Translate `mcp/servers.json` into `extensions` in `config.yaml`.
- serena needs a non-Claude context: use the neutral args (without `--context claude-code`) or a goose-specific `agents.goose` override in the manifest.

## Caveats

- Skill de-duplication: goose reads both skill directories; do not link the same skill into both.
- Symlink support for hints files and skills is undocumented: test it.
- License Apache-2.0, actively released (Nov 2026).
