# Rule Refinements (#15, #16, #17) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Rule 9 operational, rewrite Rule 3 so it no longer conflicts with the superpowers implementer prompt, and rewrite the Claude model-routing section. All three go in one PR.

**Architecture:** Text-only edits to three rule-layer files, each guarded by a content test in `tests/test_rules.sh`. One task = one commit on branch `feat/rule-refinements`.

**Tech Stack:** Markdown rule files; plain-bash tests (`tests/run.sh`, `tests/lib.sh` helpers `assert_eq`, `assert_contains`, `fail`).

**Spec:** GitHub issues #15, #16, #17. The decisions are recorded in their bodies, and #17 has a "Decisions" section. The overlap analysis behind them is in the comment on #2.

## Global Constraints

- English only in files, tests, commits and branch names.
- Rule numbers never change. Rule 6 stays retired. `test_rule_numbers_unique` must keep passing.
- Neutral files (`AGENTS.md`, `profiles/dev.md`, `rules/*.md`) must not mention opus, sonnet, superpowers, serena, context7, `CLAUDE_CODE_` or `~/.claude` (`test_neutral_files_have_no_claude_terms`).
- Edit in place. Do not add a second section on the same topic (Rule 7).
- Commit messages: no co-author trailer, no "Generated with" footer. Do not push (Rule 16). The controller pushes once and opens one PR with `Closes #15`, `Closes #16`, `Closes #17`.
- Verification command for every task: `bash tests/run.sh` → every line `PASS`, exit 0.

## Review Focus

- Rule 9 in `profiles/dev.md` or Rule 3 in `AGENTS.md` accidentally gains a Claude/superpowers term → the neutral-file test must fail. Check that it stays green only because the wording is neutral.
- The model-routing section is duplicated instead of replaced → `test_model_routing_single_section` counts headings.
- The heading text of Rule 9 changes → `test_rule_numbers_unique` still parses `## Rule 9 — ...`. Keep the heading identical.

---

### Task 1: Make Rule 9 operational (#15)

**Files:**
- Modify: `profiles/dev.md` (body line under `## Rule 9 — Tests verify intent`; heading unchanged)
- Test: `tests/test_rules.sh`

- [ ] **Step 1: Write the failing test** `test_rule9_is_operational` in `tests/test_rules.sh`. Extract the Rule 9 body (lines after `## Rule 9` up to the next `## ` heading) from `profiles/dev.md`. Then:
  - `assert_contains "$body" 'production change'`
  - `assert_contains "$body" 'Tests encode WHY behavior matters'`
- [ ] **Step 2: Run `bash tests/run.sh`.** Expected: `FAIL test_rule9_is_operational`, all others PASS.
- [ ] **Step 3: Replace the Rule 9 body with exactly:**

```
Tests encode WHY behavior matters. A test that cannot fail when the business logic changes is wrong. Before writing a test, name the production change (a realistic bug) that would make it fail. Take expected values from the spec or a worked example, never recomputed the way the code does.
```

- [ ] **Step 4: Run `bash tests/run.sh`.** Expected: all PASS.
- [ ] **Step 5: Commit** `profiles/dev.md` and `tests/test_rules.sh` with the message `Make Rule 9 operational: name the failing production change (#15)`.

### Task 2: Rewrite Rule 3 to adopt the "improve the code you are changing" boundary (#16)

**Files:**
- Modify: `AGENTS.md` (body line under `## Rule 3 — Surgical Changes`; heading unchanged)
- Test: `tests/test_rules.sh`

Background: superpowers 7.0.2 `subagent-driven-development/implementer-prompt.md` says "Improve code you're touching the way a good developer would, but don't restructure things outside your task." The current Rule 3 is in tension with it. The user decided (2026-11-23) to adopt that boundary in Rule 3 itself, as an always-on, agent-neutral rule. With that change the conflict disappears, so no override line is added to `agents/claude/dev.md`. `AGENTS.md` is a neutral file: do not mention superpowers.

- [ ] **Step 1: Write the failing test** `test_rule3_scopes_improvements_to_changed_code`. Extract the Rule 3 body (lines after `## Rule 3` up to the next `## ` heading) from `AGENTS.md`, then:
  - `assert_contains "$body" 'Inside the code you are already changing'`
  - `assert_contains "$body" 'Report other improvements'`
  - `assert_contains "$body" 'Match existing style'`
- [ ] **Step 2: Run `bash tests/run.sh`.** Expected: only the new test FAILs.
- [ ] **Step 3: Replace the Rule 3 body with exactly:**

```
Touch only what the task needs. Inside the code you are already changing, improve it the way a good developer would. Don't "improve" adjacent code, comments, or formatting, and don't restructure anything outside the task. Clean up only your own mess. Match existing style. Report other improvements you notice instead of applying them.
```

- [ ] **Step 4: Run `bash tests/run.sh`.** Expected: all PASS.
- [ ] **Step 5: Commit** `AGENTS.md` and `tests/test_rules.sh` with the message `Rule 3: allow improving the code being changed, report the rest (#16)`.

### Task 3: Rewrite the Claude model-routing section (#17)

**Files:**
- Modify: `agents/claude/CLAUDE.md` (replace the body of `# Model routing — MANDATORY`; keep the heading)
- Test: `tests/test_rules.sh`

- [ ] **Step 1: Write the failing test** `test_model_routing_single_section`:
  - `grep -c '^# Model routing' agents/claude/CLAUDE.md` equals `1`.
  - The section body (from that heading up to the next `# ` heading) contains `Opus 5.5`, `code review`, `web research` and `judges their findings`.
- [ ] **Step 2: Run `bash tests/run.sh`.** Expected: only the new test FAILs.
- [ ] **Step 3: Replace the section body with exactly:**

```
- The main agent runs on Opus (currently Opus 5.5; settings keep the `opus` alias) and acts EXCLUSIVELY as architect, analyst, judge, and orchestrator: design, requirements and solution analysis, planning, decomposition, accepting or rejecting subagent work, talking to the user.
- Sonnet is MANDATORY (Agent tool, `model: "sonnet"`) for: software development (implementation, tests, debugging legwork); code review and code analysis; web research for documentation; codebase exploration and searches; reading and summarizing documents. `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` is the fallback for skill-launched subagents.
- Code review split: Sonnet reviewer subagents review the code; Opus only judges their findings and decides accept or reject. Opus does not review code line by line.
- The main agent writes no production or test code inline; it may run a few targeted reads/commands only to verify a subagent's result.
```

- [ ] **Step 4: Run `bash tests/run.sh`.** Expected: all PASS.
- [ ] **Step 5: Commit** with the message `Rewrite model routing: Opus architect/analyst, Sonnet for dev, review, research (#17)`.

### After all tasks (controller)

- Tick the matching checklist items in #15, #16 and #17 with `gh issue edit`.
- Run one final whole-branch review. Push once. Open one PR with `Closes #15`, `Closes #16`, `Closes #17`.
- Live loading check (`/memory`): the repo is not installed on this machine yet (`~/.agent-dotfiles` is absent; cutover is #14). The user decided to move this check to #14; it was removed from #16 and #17.
