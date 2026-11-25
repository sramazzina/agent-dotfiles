LAYERS="AGENTS.md profiles/dev.md agents/claude/dev.md"
NEUTRAL="AGENTS.md profiles/dev.md languages/*.md"

test_rule_numbers_unique() {
  cd "$REPO_ROOT"
  local got want
  got="$(cat $LAYERS | sed -n 's/^## Rule \([0-9]\+\) .*/\1/p' | sort -n | tr '\n' ' ')"
  # Rule 6 is retired and has no heading; the other numbers never shift (project docs cite them).
  want="$(seq 1 16 | grep -vx 6 | tr '\n' ' ')"
  assert_eq "$want" "$got" "rule numbers across layers"
}

test_rule6_retirement_stated() {
  cd "$REPO_ROOT"
  local f
  for f in $LAYERS; do
    grep -qF 'Rule 6 is retired' "$f" || fail "$f: Rule 6 retirement note"
  done
}

test_neutral_files_have_no_claude_terms() {
  cd "$REPO_ROOT"
  ls $NEUTRAL >/dev/null || fail "neutral files missing"
  if grep -niE 'opus|sonnet|superpowers|serena|context7|CLAUDE_CODE_|~/\.claude' $NEUTRAL; then
    fail "agent-specific term in neutral file"
  fi
}

test_claude_entries_import_existing_files() {
  cd "$REPO_ROOT"
  local n=0 p
  while IFS= read -r p; do
    [ -f "$p" ] || fail "import target missing: $p"
    n=$((n+1))
  done < <(sed -n 's|^@~/.agent-dotfiles/\(.*\)$|\1|p' agents/claude/*.md)
  [ "$n" -ge 2 ] || fail "expected at least 2 imports, found $n"
}

test_language_files_have_no_frontmatter() {
  cd "$REPO_ROOT"
  local f
  for f in languages/*.md; do
    [ "$(head -n1 "$f")" != "---" ] || fail "frontmatter in $f"
  done
  grep -qF 'mvn -pl <module> -am -DskipITs verify' languages/java.md || fail "java verify command"
}

test_skill_frontmatter() {
  cd "$REPO_ROOT"
  local fm
  fm="$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' skills/serena-query-project/SKILL.md)"
  assert_contains "$fm" 'name: serena-query-project' "skill name"
  echo "$fm" | grep -qE '^description: *[^ ]' || fail "empty description"
}

test_commit_hygiene_universal() {
  cd "$REPO_ROOT"
  grep -qi 'co-author' AGENTS.md || fail "AGENTS.md co-author"
  grep -q 'Generated with' AGENTS.md || fail "AGENTS.md footer"
  if grep -qiE 'co-author|Generated with' profiles/dev.md; then fail "commit hygiene duplicated in dev"; fi
}

test_dev_profile_check_present() {
  cd "$REPO_ROOT"
  grep -qi '^#.*Dev profile check' agents/claude/CLAUDE.md || fail "heading"
  grep -qF '~/.agent-dotfiles/install.sh --enable-dev' agents/claude/CLAUDE.md || fail "install cmd"
  if grep -q -- '--enable-dev' AGENTS.md profiles/dev.md; then fail "--enable-dev leaked"; fi
}

test_workflow_skills_are_always_obligations() {
  cd "$REPO_ROOT"
  grep -qE 'ALWAYS.*superpowers:brainstorming' agents/claude/CLAUDE.md || fail "ALWAYS brainstorming"
  grep -qE 'ALWAYS.*superpowers:writing-plans' agents/claude/CLAUDE.md || fail "ALWAYS writing-plans"
}

test_rule9_is_operational() {
  cd "$REPO_ROOT"
  local body
  body="$(awk '/^## Rule 9/{f=1;next} f&&/^## /{exit} f' profiles/dev.md)"
  assert_contains "$body" 'production change' "rule 9 names production change"
  assert_contains "$body" 'Tests encode WHY behavior matters' "rule 9 keeps intent sentence"
}

test_rule3_scopes_improvements_to_changed_code() {
  cd "$REPO_ROOT"
  local body
  body="$(awk '/^## Rule 3/{f=1;next} f&&/^## /{exit} f' AGENTS.md)"
  assert_contains "$body" 'Inside the code you are already changing' "rule 3 allows improving changed code"
  assert_contains "$body" 'Report other improvements' "rule 3 reports other improvements"
  assert_contains "$body" 'Match existing style' "rule 3 keeps style sentence"
}

test_model_routing_single_section() {
  cd "$REPO_ROOT"
  assert_eq "1" "$(grep -c '^# Model routing' agents/claude/CLAUDE.md)" "one model routing heading"
  local body
  body="$(awk '/^# Model routing/{f=1;next} f&&/^# /{exit} f' agents/claude/CLAUDE.md)"
  assert_contains "$body" 'Opus 5.5' "names current Opus"
  assert_contains "$body" 'code review' "code review delegated"
  assert_contains "$body" 'web research' "web research delegated"
  assert_contains "$body" 'judges their findings' "Opus judges findings"
  assert_contains "$body" 'ask the user first' "escalation asks the user"
}

test_dev_profile_check_mentions_lang() {
  cd "$REPO_ROOT"
  sed -n '/^# Dev profile check/,$p' agents/claude/CLAUDE.md | grep -qF -- '--lang' \
    || fail "Dev profile check does not mention --lang"
}

test_readme_has_no_path_scoped_language_layer() {
  cd "$REPO_ROOT"
  if grep -qF 'paths:' README.md; then fail "README still mentions paths: auto-activation"; fi
  grep -qF -- '--lang' README.md || fail "README does not mention --lang"
}
