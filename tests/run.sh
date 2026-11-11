#!/usr/bin/env bash
# Runs every tests/test_*.sh. Each file registers tests with: t "<name>" <command...>
# A test passes when its command exits 0. Prints "ok - <name>" / "not ok - <name>".
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILED=0
PASSED=0

t() {
  local name=$1 rc
  shift
  # why: set -e is ignored inside an `if` condition, so run the subshell first and read $? after.
  (set -e; "$@") >"$WORK/log" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "ok - $name"
    PASSED=$((PASSED + 1))
  else
    echo "not ok - $name"
    sed 's/^/#   /' "$WORK/log"
    FAILED=$((FAILED + 1))
  fi
}

for f in tests/test_*.sh; do
  # shellcheck source=/dev/null
  . "$f"
done

echo "# passed $PASSED, failed $FAILED"
[ "$FAILED" -eq 0 ]
