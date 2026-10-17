# Windows PowerShell equivalent of tools/verify.sh
# Usage: pwsh -File tools/verify.ps1
$ErrorActionPreference = "Continue"
$OUT = "docs/grokbot/audit_input"
New-Item -ItemType Directory -Force -Path $OUT | Out-Null

Write-Host "== analyze =="
flutter analyze 2>&1 | Tee-Object -FilePath "$OUT/analyze.txt"
$ANALYZE_RC = $LASTEXITCODE
Get-Content "$OUT/analyze.txt"

Write-Host "== test =="
flutter test 2>&1 | Tee-Object -FilePath "$OUT/test.txt"
$TEST_RC = $LASTEXITCODE
Get-Content "$OUT/test.txt" | Select-Object -Last 5

Write-Host "analyze_rc=$ANALYZE_RC test_rc=$TEST_RC"
if ($ANALYZE_RC -ne 0 -or $TEST_RC -ne 0) {
  Write-Host "VERIFY: FAILED"
  exit 1
}
Write-Host "VERIFY: OK"
