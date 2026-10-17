# Windows PowerShell equivalent of tools/verify.sh
# Usage: powershell -File tools/verify.ps1
$ErrorActionPreference = "Continue"
$OUT = "docs/grokbot/audit_input"
New-Item -ItemType Directory -Force -Path $OUT | Out-Null

function Write-Utf8File([string]$Path, [string]$Text) {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath (Split-Path $Path -Parent) | Join-Path -ChildPath (Split-Path $Path -Leaf)), $Text, $utf8)
}

Write-Host "== analyze =="
$analyzeOut = & flutter analyze 2>&1 | Out-String
$ANALYZE_RC = $LASTEXITCODE
$analyzePath = Join-Path $OUT "analyze.txt"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path (Get-Location) $analyzePath), $analyzeOut, $utf8)
Get-Content $analyzePath

Write-Host "== test =="
$testOut = & flutter test 2>&1 | Out-String
$TEST_RC = $LASTEXITCODE
$testPath = Join-Path $OUT "test.txt"
[System.IO.File]::WriteAllText((Join-Path (Get-Location) $testPath), $testOut, $utf8)
Get-Content $testPath | Select-Object -Last 5

Write-Host "analyze_rc=$ANALYZE_RC test_rc=$TEST_RC"
if ($ANALYZE_RC -ne 0 -or $TEST_RC -ne 0) {
  Write-Host "VERIFY: FAILED"
  exit 1
}
Write-Host "VERIFY: OK"
