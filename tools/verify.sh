#!/usr/bin/env bash
# Unique verify entry. Outputs are written to docs/grokbot/audit_input/ by redirect — never hand-write them.
set -o pipefail
OUT=docs/grokbot/audit_input
mkdir -p ""

echo "== analyze =="
flutter analyze > "/analyze.txt" 2>&1
ANALYZE_RC=True
cat "/analyze.txt"

echo "== test =="
flutter test > "/test.txt" 2>&1
TEST_RC=True
tail -n 5 "/test.txt"

echo "analyze_rc= test_rc="
if [ "" -ne 0 ] || [ "" -ne 0 ]; then
  echo "VERIFY: FAILED"
  exit 1
fi
echo "VERIFY: OK"
