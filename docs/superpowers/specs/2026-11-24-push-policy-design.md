# Push policy — Design

Date: 2026-11-24 · Status: approved by the user (2026-11-24), with the docs-only exception added on approval
Amends: `2026-11-24-irreversible-ops-guard-design.md` (§4 `git push` item, §6.1 rules, §6.2 "no git calls").

## 1. Intent

The guard shipped in PR #22 makes every `git push` prompt. The user wants a different rule:

- Pushing a **feature branch** to `origin` is free: no prompt.
- Pushing to **`main`/`master`**, or to the **`upstream`** remote, happens only when the user explicitly asked for it in the conversation. When they did, there is no further prompt.

- **Exception kept from the dev profile** (`profiles/dev.md` "Git and PR rules": `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/HANDOFF*.md` go directly to `main`): a non-forced push to `main`/`master` on a non-`upstream` remote whose outgoing commits change only those files is free, like a feature-branch push. Requested by the user on approval of this design.

Everything else in the guard policy stays as it is (merge, release, deploy, secrets, mutating `gh api` keep asking; `gh repo delete` and force push to `main`/`master` stay denied).

## 2. Goals, non-goals, anti-goals

**Goals**
- No prompt for pushes whose destinations are all non-protected branches on a non-`upstream` remote.
- A push to `main`/`master` or to `upstream` that the user did not explicitly ask for does not run.
- A push to `main`/`master` or `upstream` the user explicitly asked for runs without a prompt.

**Non-goals**
- Deterministic recognition of "the user asked". Only the auto-mode classifier reads the conversation; this is a model judgement, not a rule.
- Changing the other policy items.

**Anti-goals**
- A project `allow` rule (`Bash(git:*)`, `Bash(git push *)`) letting a protected push through without any check.
- A protected push slipping through when the session is not in auto mode.

## 3. Verified facts and facts to verify

From the Claude Code docs (checked 2026-11-24, see the guard design §3):
- `allow` rules skip the auto-mode classifier. `autoMode.classifyAllShell: true` suspends all Bash/PowerShell `allow` rules in auto mode, so every shell command goes through the classifier.
- `autoMode.soft_deny` entries are prose rules for the classifier; "explicit user intent" can clear a soft deny. `"$defaults"` keeps the built-in entries. `autoMode` is read only from user settings, managed settings and `--settings`.
- By default the classifier allows pushing to any branch, including the default branch.

To verify during implementation (docs, then a live check at cutover):
- The PreToolUse hook input carries `permission_mode` and `cwd`.
- A soft-deny entry is cleared when the user explicitly asked for the action, and not otherwise.

## 4. Approaches

- **A. Classifier decides, nothing bypasses it — chosen by the user.** Hook stays silent on pushes outside auto mode concerns; a `soft_deny` entry blocks protected pushes unless the user explicitly asked; `classifyAllShell: true` stops project `allow` rules from skipping the classifier.
- **B. Deterministic `ask` on protected pushes.** Always one prompt, even when the user asked. Rejected: the user does not want the extra confirmation.
- **C. Deterministic `deny` on protected pushes; the user runs them with `!`.** Rejected: the user wants the agent to run them on request.

## 5. Design

### 5.1 Hook (`hooks/guard-irreversible.sh`)

`git push` classification, per segment, after the existing normalisation:

1. **Resolve destinations.**
   - Remote: the first non-option argument after `push`; if absent, `git config branch.<current>.remote`, else `origin`.
   - Branches: each refspec's destination (existing rules: part after `:`, or the whole refspec; `+` stripped; `refs/heads/` stripped; `HEAD` means the current branch). With no refspec, the destination is the current branch.
   - Current branch: `git -C <dir> rev-parse --abbrev-ref HEAD`, where `<dir>` is the `-C` value if given, else the hook input's `cwd`. A local, read-only git call. This replaces the guard design's "no git calls" constraint for this case only.
   - `--tags`, `--all`, `--mirror`: treated as protected (they publish more than one feature branch).
   - Unknown (detached HEAD, git call fails, unparseable): treated as protected.
   - **Docs-only check** (only for a non-forced push to `main`/`master` on a non-`upstream` remote): list the files changed by the outgoing commits with `git -C <dir> log --name-only --format= <remote>/<dest>..<source>` (source = the refspec's source side, or the current branch). If the list is non-empty and every path is `README.md`, `CLAUDE.md`, `CHANGELOG.md` (repo root) or matches `docs/HANDOFF*.md`, the push is **docs-only**. A missing remote-tracking ref or a failing git call means not docs-only (safe side; a stale remote-tracking ref can only add files, never hide them).
2. **Decide.**
   - Forced and a destination is `main`/`master` → `deny` (unchanged).
   - Deleting a remote `main`/`master` (`--delete main`, `:main`) → `deny` (builder's call recorded here: same harm as a force push).
   - Docs-only push (above) → no decision, in every mode.
   - Protected (a destination is `main`/`master`, or the remote is `upstream`, or the case is unknown/`--tags`/`--all`/`--mirror`):
     - `permission_mode` is `auto` → no decision (the classifier rules, §5.3).
     - any other mode → `ask` (no classifier outside auto mode; prevents project `allow` rules from letting it through).
   - Otherwise (feature branches on a non-`upstream` remote, including force pushes and deletions of feature branches) → no decision.

### 5.2 Rules (`agents/claude/settings.fragment.json`)

Remove `Bash(git push *)` from `enforce.permissions.ask`. All other entries stay.

Because the installer merges permission lists by union, the old entry stays in the user's `settings.json`. The cutover removes it by hand (guard design §6.3, known limitation).

### 5.3 Auto mode (`agents/claude/settings.fragment.json`, `enforce.autoMode`)

- `classifyAllShell: true`.
- `soft_deny`: `"$defaults"` plus one entry, exact text:
  `git push to the main or master branch, or to the remote named upstream, of any repository — unless the user explicitly asked for that push in this conversation. This includes pushes with --tags, --all or --mirror. Exception: a non-forced push to main or master on a remote other than upstream whose commits change only README.md, CLAUDE.md, CHANGELOG.md or docs/HANDOFF*.md is allowed without asking (the dev profile's direct-to-main exception).`

  The classifier cannot run git, so in auto mode it judges the docs-only exception from the conversation (the commits it saw being made). The hook's deterministic docs-only check covers the other modes.

Installer: `autoMode.soft_deny` (and `autoMode.allow`, `autoMode.hard_deny`, `autoMode.environment` if the fragment ever defines them) merge by union, like the permission lists; `classifyAllShell` is enforced. Other local `autoMode` keys are kept.

### 5.4 Stale `autoMode` block

The user's `settings.json` carries an `autoMode` block written for another repository (`iceberg-platform-poc`: `environment` and two `soft_deny` entries). The cutover shows it to the user and removes it with their approval, after the installer's backup. Not automated.

### 5.5 Tests

- Hook (`tests/test_guard_hook.sh`), with a temporary git repo for the current-branch cases and `permission_mode` in the input:
  - no decision: `git push origin feat/x` (auto and default mode); `git push` on branch `feat/x`; `git push -u origin HEAD` on `feat/x`; `git push --force origin feat/x`; `git push origin --delete feat/x`
  - no decision in auto mode, `ask` in default mode: `git push origin main`; `git push` on branch `main`; `git push upstream feat/x`; `git push --tags`; `git push` on a detached HEAD
  - deny (any mode): `git push -f origin main`; `git push origin --delete main`; `git push origin :master`
  - docs-only (temporary repo with a bare remote): `git push origin main` whose outgoing commit changes only `CHANGELOG.md` → no decision in default mode; outgoing commits changing `CHANGELOG.md` and `src/App.java` → `ask` in default mode; changing only `docs/HANDOFF-x.md` → no decision; `git push -f origin main` docs-only → still `deny`; `git push upstream main` docs-only → `ask` in default mode; no remote-tracking ref → `ask` in default mode
- Settings (`tests/test_install_settings.sh`): fragment no longer contains `Bash(git push *)`; `autoMode.classifyAllShell` is `true`; the soft-deny entry is present once after two installs; a user's own `autoMode.soft_deny` entry survives.

### 5.6 Documentation

README guard section: the push rule in plain words, the role of the classifier, the `classifyAllShell` effect (project `allow` lists no longer skip the classifier in auto mode), and the manual cutover steps. `docs/verification.md`: cutover checks for the four push cases (feature branch free; `main` without asking blocked; `main` when asked runs without a prompt; default mode asks).

## 6. Consequences to accept

- **Every shell command in auto mode goes through the classifier.** Commands that project allow lists used to approve instantly now take a classifier call (latency, cost). Phase 2's shared allow list loses most of its value in auto mode; it still matters in other modes.
- **"The user asked" is a model judgement.** It can occasionally block a push you asked for (you then confirm or rephrase) or, rarely, let one through on ambiguous wording.

## 7. Left to the builder

Parsing details for remotes and refspecs within §5.1; exact reason strings; test harness details.
