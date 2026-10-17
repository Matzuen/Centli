#!/usr/bin/env bash
# Unique verify entry. Outputs are written to docs/grokbot/audit_input/ by redirect — never hand-write them.
# G25: delete artifacts first, then generate, then assert non-empty / exist.
set -o pipefail
OUT=docs/grokbot/audit_input
mkdir -p "$OUT"

# 1) Delete generated artifacts first (keep notes.md).
rm -f "$OUT"/analyze.txt "$OUT"/test.txt "$OUT"/HEAD.txt \
      "$OUT"/status.txt "$OUT"/commits.txt "$OUT"/diff_stat.txt

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

# 3) Existence / non-empty asserts (fail if generation skipped).
for f in analyze.txt test.txt HEAD.txt commits.txt; do
  [ -s "$OUT/$f" ] || { echo "AUDIT INPUT MISSING/EMPTY: $f"; exit 1; }
done
# status/diff_stat may legitimately be empty — only require file exists.
for f in status.txt diff_stat.txt; do
  [ -f "$OUT/$f" ] || { echo "AUDIT INPUT MISSING: $f"; exit 1; }
done
if [ ! -s "$OUT/HEAD.txt" ] || [ "$(tr -d '\r\n' < "$OUT/HEAD.txt")" != "$(git rev-parse HEAD)" ]; then
  echo "AUDIT INPUT HEAD MISMATCH"
  exit 1
fi

echo "analyze_rc=$ANALYZE_RC test_rc=$TEST_RC"
if [ "$ANALYZE_RC" -ne 0 ] || [ "$TEST_RC" -ne 0 ]; then
  echo "VERIFY: FAILED"
  exit 1
fi
echo "VERIFY: OK"
