#!/usr/bin/env bash
# Unique verify entry. Outputs are written to docs/grokbot/audit_input/ by redirect — never hand-write them.
set -o pipefail
OUT=docs/grokbot/audit_input
mkdir -p "$OUT"

echo "== analyze =="
flutter analyze > "$OUT/analyze.txt" 2>&1
ANALYZE_RC=$?
cat "$OUT/analyze.txt"

echo "== test =="
flutter test > "$OUT/test.txt" 2>&1
TEST_RC=$?
tail -n 5 "$OUT/test.txt"

echo "analyze_rc=$ANALYZE_RC test_rc=$TEST_RC"
if [ "$ANALYZE_RC" -ne 0 ] || [ "$TEST_RC" -ne 0 ]; then
  echo "VERIFY: FAILED"
  exit 1
fi
echo "VERIFY: OK"
