# agent-dotfiles

Personal, versioned configuration for coding agents: behavioral rules, skills and MCP server definitions. Cloned on every Linux server where agents run and wired into each agent's home configuration by `install.sh`.

Today only Claude Code is wired; the layout is agent-neutral so opencode, pi or goose can be added later.

Status: design approved, implementation not started.

- Design: [`docs/superpowers/specs/2026-11-23-agent-dotfiles-design.md`](docs/superpowers/specs/2026-11-23-agent-dotfiles-design.md)
- Bootstrap handoff: [`HANDOFF-2026-11-23-bootstrap.md`](HANDOFF-2026-11-23-bootstrap.md)
- Migration of existing projects: deferred, see issue #1.
