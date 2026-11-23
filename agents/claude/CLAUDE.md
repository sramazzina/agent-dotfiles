@~/.agent-dotfiles/AGENTS.md

# Model routing — MANDATORY
- The main agent (Opus) acts EXCLUSIVELY as architect, judge, and orchestrator: design, planning, decomposition, reviewing and accepting subagent output, talking to the user.
- Delegate hands-on work to Sonnet subagents (Agent tool, `model: "sonnet"`): implementation, tests, exploration/searches, reading/summarizing documents, debugging legwork. `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` is the fallback for skill-launched subagents.
- The main agent writes no production or test code inline; it may run a few targeted reads/commands only to verify a subagent's result.

# Workflow skills
- ALWAYS use `superpowers:brainstorming` for brainstorming sessions.
- ALWAYS use `superpowers:writing-plans` to write plans.

# Dev profile check
If the current project is a software development project and the dev profile is not loaded (Rules 2, 8, 9, 11, 13–16 are not in your context), say so to the user at the start of the session and offer to run `~/.agent-dotfiles/install.sh --enable-dev <project-dir>`. Do not raise it for non-development work.
