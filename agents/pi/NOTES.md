# pi adapter notes (not implemented)

Facts from the design spec section 3, checked 2026-11-23. Re-verify before building.

- **Global instruction file:** `~/.pi/agent/AGENTS.md`.
- **Imports:** none. There is no include syntax.
- **Skills:** reads `~/.agents/skills` (Agent Skills `SKILL.md` format).
- **Config / MCP:** not researched; check pi's own docs before building.

## Requirements for an adapter

- Because there are no imports, generate a concatenated `~/.pi/agent/AGENTS.md` (neutral `AGENTS.md`, plus `profiles/dev.md` where wanted). Rule edits then need a re-run of the installer, and the generated file must be marked "do not edit".
- Link skills into `~/.agents/skills`.

## Caveats

- Skill de-duplication: if other agents that read both skill directories are also installed, avoid linking the same skill into both locations.
- Symlink support for skills is undocumented: test it.
- License MIT/Apache-2.0, actively released (Nov 2026).
