#!/usr/bin/env bash
# Runs every test_* function of every tests/test_*.sh, each in a subshell.
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
failed=0
log="$(mktemp)"
for f in tests/test_*.sh; do
  [ -e "$f" ] || continue
  for t in $(bash -c "source '$f'; declare -F" | awk '{print $3}' | grep '^test_'); do
    # not in an if-condition: errexit must stay active inside the subshell
    ( set -euo pipefail; source tests/lib.sh; source "$f"; trap teardown_home EXIT; "$t" ) >"$log" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "PASS $t"
    else
      echo "FAIL $t"; sed 's/^/    /' "$log"; failed=1
    fi
  done
done
rm -f "$log"
exit $failed
