LAYERS="AGENTS.md profiles/dev.md agents/claude/dev.md"
NEUTRAL="AGENTS.md profiles/dev.md rules/*.md"

test_rule_numbers_unique() {
  cd "$REPO_ROOT"
  local got want
  got="$(cat $LAYERS | sed -n 's/^## Rule \([0-9]\+\) .*/\1/p' | sort -n | tr '\n' ' ')"
  want="$(seq 1 16 | tr '\n' ' ')"
  assert_eq "$want" "$got" "rule numbers across layers"
}

test_rule6_reserved() {
  cd "$REPO_ROOT"
  grep -qxF '## Rule 6 — (retired; number reserved)' AGENTS.md || fail "Rule 6 heading"
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

test_java_rule_paths() {
  cd "$REPO_ROOT"
  local fm
  fm="$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' rules/java.md)"
  assert_contains "$fm" 'paths:' "frontmatter paths"
  assert_contains "$fm" '**/*.java' "java glob"
  assert_contains "$fm" '**/pom.xml' "pom glob"
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
