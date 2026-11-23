---
name: serena-query-project
description: Use when exploring a codebase that is not the active Serena project, e.g. Apache Hop from a plugin project
---
# Using Serena `query_project` on another project
Use this procedure whenever you need to explore a codebase that is **not** the currently active Serena project (typical case: inspecting the Apache Hop source from within a plugin project).

1. **Verify the target project is registered in Serena**
   - List known projects with `list_memories` / inspect `~/.serena/serena_config.yml`.
   - If missing, register it by calling `activate_project(project="<absolute/path/to/project>")` once — Serena adds it to its config automatically.
2. **Ensure the target has a `.serena/project.yml`**
   - If absent, run Serena's `onboarding` tool on that path, or create the file manually specifying at minimum the `language` (e.g. `java`).
   - Without this file the Language Server cannot start and `query_project` will fail.
3. **Pre-index large codebases** (recommended for Apache Hop and similarly sized repos) to avoid first-call timeouts:
   ```bash
   uvx --from git+https://github.com/oraios/serena serena project index <absolute/path/to/project>
   ```
   This populates `.serena/cache/` with the symbol index.
4. **Activate the target project** in the current session:
   `activate_project(project="<name-or-absolute-path>")`.
   Remember: Serena keeps **one active project per session** — switching deactivates the previous one.
5. **Run the query** with `query_project(query="<natural-language question>")`. Prefer focused questions (symbol name, package, behaviour) over broad ones; Serena internally uses its symbolic tools to answer.
6. **Restore the original project** when finished by calling `activate_project` again with the path of the project you were originally working on, so subsequent edits land in the right place.

Notes:
- Never use `Read`/`Grep` on the foreign codebase as a substitute — always go through `query_project` so results come from Serena's indexed view.
- If `query_project` returns empty or stale results, re-run the indexing command from step 3.
