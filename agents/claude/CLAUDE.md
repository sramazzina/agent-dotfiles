@~/.agent-dotfiles/AGENTS.md

# Model routing — MANDATORY
- The main agent runs on Opus (currently Opus 5.5; settings keep the `opus` alias) and acts EXCLUSIVELY as architect, analyst, judge, and orchestrator: design, requirements and solution analysis, planning, decomposition, accepting or rejecting subagent work, talking to the user.
- Sonnet is MANDATORY (Agent tool, `model: "sonnet"`) for: software development (implementation, tests, debugging legwork); code review and code analysis (of existing code); web research for documentation; codebase exploration and searches; reading and summarizing documents. `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` is the fallback for skill-launched subagents.
- Code review split: Sonnet reviewer subagents review the code; Opus only judges their findings and decides accept or reject. Opus does not review code line by line.
- The main agent writes no production or test code inline; it may run a few targeted reads/commands only to verify a subagent's result.
- Escalation: when you judge that an operation needs a more capable model than this routing assigns (for example, a skill asks for "the most capable model", or a fix loop escalates), ask the user first: name the operation, the model, and why. Without a yes, follow the routing above. A standing approval the user already gave for that kind of operation counts as a yes.

# Workflow skills
- ALWAYS use `superpowers:brainstorming` for brainstorming sessions.
- ALWAYS use `superpowers:writing-plans` to write plans.

# Dev profile check
If the current project is a software development project and the dev profile is not loaded (Rules 2, 8, 9, 11, 13–16 are not in your context), say so to the user at the start of the session and offer to run `~/.agent-dotfiles/install.sh --enable-dev <project-dir> --lang <lang>`, with one `--lang` for each language of the project that has a file in `~/.agent-dotfiles/languages/`. If the dev profile is loaded but the import for the project's language is missing, say so and offer the same command. Do not raise it for non-development work.
