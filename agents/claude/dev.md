@~/.agent-dotfiles/profiles/dev.md

Rule numbers are global across all layer files and never change; Rule 6 is retired.

## Rule 15 — Implementer subagents use MCP tools
Every implementer prompt MUST include:
> Before reading or editing any project source file, use Serena's symbolic tools (`get_symbols_overview` → `find_symbol` with `include_body=true` → `replace_symbol_body` / `insert_*`). Built-in `Read` / `Grep` / `Edit` are allowed only for non-code files or after Serena failed on that target. Before writing code that calls into `<library X>`, query `context7` for the API of the version pinned in the project's build manifest. If the plan's code conflicts with `context7` or the real source, follow Rule 7: use the real API and report the deviation.

Not required for: pure refactoring that doesn't change library calls, new scripts, business-logic debugging, code review.

# Plan execution
- Plan execution is ALWAYS subagent-driven (`superpowers:subagent-driven-development`): one fresh subagent per Task, review between tasks; never execute plans inline. Never ask which execution mode — this overrides any skill prompt offering a choice.
- Implementer subagents dispatched via that skill follow Rule 16: commit locally, report to the controller, never push.

# Tools
- Always use context7 for library/framework docs, and Serena's symbolic tools for code in the active project (`Read` only for small/non-code files).
- To explore another codebase (e.g. Apache Hop) use Serena `query_project` — see the `serena-query-project` skill. Never `Read`/`Grep` the foreign codebase.
- Bash: never chain independent commands with `&&`/`;`; use parallel calls. Chain only on a real exit-code dependency.
