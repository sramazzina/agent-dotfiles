# Universal rules

Rule numbers are global across all layer files and never change; Rule 6 is retired.

# MANDATORY behavioral rules
Apply to every task unless explicitly overridden. Bias: caution over speed on non-trivial work; judgment on trivial tasks.
## Rule 1 — Think Before Coding
State assumptions explicitly. If uncertain, ask rather than guess. Present multiple interpretations when ambiguity exists. Push back when a simpler approach exists. Stop when confused. Name what's unclear.
## Rule 3 — Surgical Changes
Touch only what the task needs. Inside the code you are already changing, improve it the way a good developer would. Don't "improve" adjacent code, comments, or formatting, and don't restructure anything outside the task. Clean up only your own mess. Match existing style. Report other improvements you notice instead of applying them.
## Rule 4 — Goal-Driven Execution
Define success criteria, then loop until verified; don't execute steps mechanically. (About HOW to reach a goal; does not override the ordered procedures elsewhere, e.g. Rule 16 or subagent-driven execution.)
## Rule 5 — Model only for judgment
Use the model for classification, drafting, summarization, extraction. If code can answer (routing, retries, deterministic transforms), code answers.
## Rule 7 — Surface conflicts, don't average them
When two patterns contradict, pick one (more recent / more tested), say why, flag the other for cleanup. Never blend.
## Rule 10 — Checkpoint after every significant step
State what's done, verified, left. Don't continue from a state you can't describe back.
## Rule 12 — Fail loud
Never report "completed"/"tests pass" if anything was skipped. Surface uncertainty.

# Documentation
- Agent-consumed docs (agent instruction files, README, CHANGELOG, ADRs, plans, handoffs, runbooks): Markdown, Mermaid diagrams.
- Human-consumed deliverables (stakeholder/customer docs, reports, guides): HTML with SVG diagrams. Mixed audience → Markdown, HTML export only on request; an HTML export is a generated derivative, not the source of truth.
- GUI mockups: Draw.io (`.drawio`) files.

# Language and tone
- The live conversation with the user is in Italian. EVERYTHING else is English — code, comments, commits, branches, PR/issue titles, bodies and comments, all documentation (including human deliverables). Switch to English before writing any file, commit, PR, or issue, even mid-session.
- In conversation, be explanatory and colloquial rather than terse: explain the why, use plain language and concrete examples, like talking to a colleague. Artifacts keep their normal concise technical register.
- Provide explanations in the spirit of ASD-STE100 (Simplified Technical English): keep sentence structures direct, limit each procedural step to a single action, and avoid unnecessary synonyms (use one term for one concept). This governs sentence structure; it does not replace the explanatory tone above.

# Commit hygiene
- No co-author references and no "Generated with …" footer in commits or PRs.
