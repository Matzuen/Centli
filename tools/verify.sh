#!/usr/bin/env bash
# Unique verify entry. Outputs are written to docs/grokbot/audit_input/ by redirect — never hand-write them.
set -o pipefail
OUT=docs/grokbot/audit_input
mkdir -p "$OUT"
START_EPOCH=$(date +%s)

echo "== analyze =="
flutter analyze > "$OUT/analyze.txt" 2>&1
ANALYZE_RC=$?
cat "$OUT/analyze.txt"

echo "== test =="
flutter test > "$OUT/test.txt" 2>&1
TEST_RC=$?
tail -n 5 "$OUT/test.txt"

# Git snapshot inputs (always overwrite — never hand-write).
git rev-parse HEAD > "$OUT/HEAD.txt"
git status --short > "$OUT/status.txt"
git log --oneline -20 > "$OUT/commits.txt"
git diff --stat > "$OUT/diff_stat.txt"

# Freshness self-assert: HEAD.txt must match live HEAD.
HEAD_FILE=$(tr -d '\r\n' < "$OUT/HEAD.txt")
HEAD_LIVE=$(git rev-parse HEAD)
if [ "$HEAD_FILE" != "$HEAD_LIVE" ]; then
  echo "AUDIT INPUT STALE: HEAD.txt != git HEAD"
  exit 1
fi

# analyze/test must have been written during this run (mtime >= start).
analyze_mtime=$(stat -c %Y "$OUT/analyze.txt" 2>/dev/null || stat -f %m "$OUT/analyze.txt")
test_mtime=$(stat -c %Y "$OUT/test.txt" 2>/dev/null || stat -f %m "$OUT/test.txt")
if [ "$analyze_mtime" -lt "$START_EPOCH" ] || [ "$test_mtime" -lt "$START_EPOCH" ]; then
  echo "AUDIT INPUT STALE: analyze.txt/test.txt older than this verify run"
  exit 1
fi

echo "analyze_rc=$ANALYZE_RC test_rc=$TEST_RC"
if [ "$ANALYZE_RC" -ne 0 ] || [ "$TEST_RC" -ne 0 ]; then
  echo "VERIFY: FAILED"
  exit 1
fi
echo "VERIFY: OK"