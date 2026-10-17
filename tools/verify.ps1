# Windows PowerShell equivalent of tools/verify.sh
# Usage: powershell -File tools/verify.ps1
# G25: delete artifacts first, then generate, then assert non-empty / exist.
$ErrorActionPreference = "Continue"
$OUT = "docs/grokbot/audit_input"
New-Item -ItemType Directory -Force -Path $OUT | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$root = (Get-Location).Path

function Write-Utf8([string]$RelPath, [string]$Text) {
  $full = Join-Path $root $RelPath
  [System.IO.File]::WriteAllText($full, $Text, $utf8)
}

# 1) Delete generated artifacts first (keep notes.md).
@(
  "analyze.txt", "test.txt", "HEAD.txt",
  "status.txt", "commits.txt", "diff_stat.txt"
) | ForEach-Object {
  $p = Join-Path $OUT $_
  if (Test-Path $p) { Remove-Item -Force $p }
}

Write-Host "== analyze =="
$analyzeOut = & flutter analyze 2>&1 | Out-String
$ANALYZE_RC = $LASTEXITCODE
Write-Utf8 (Join-Path $OUT "analyze.txt") $analyzeOut
Get-Content (Join-Path $OUT "analyze.txt")

Write-Host "== test =="
$testOut = & flutter test 2>&1 | Out-String
$TEST_RC = $LASTEXITCODE
Write-Utf8 (Join-Path $OUT "test.txt") $testOut
Get-Content (Join-Path $OUT "test.txt") | Select-Object -Last 5

# Git snapshot inputs (always overwrite — never hand-write). UTF-8 no BOM.
$head = (& git rev-parse HEAD 2>&1 | Out-String).Trim()
Write-Utf8 (Join-Path $OUT "HEAD.txt") ($head + "`n")
$status = & git status --short 2>&1 | Out-String
Write-Utf8 (Join-Path $OUT "status.txt") $status
$commits = & git log --oneline -20 2>&1 | Out-String
Write-Utf8 (Join-Path $OUT "commits.txt") $commits
$diffStat = & git diff --stat 2>&1 | Out-String
Write-Utf8 (Join-Path $OUT "diff_stat.txt") $diffStat

# 3) Existence / non-empty asserts (fail if generation skipped).
foreach ($f in @("analyze.txt", "test.txt", "HEAD.txt", "commits.txt")) {
  $full = Join-Path $root (Join-Path $OUT $f)
  if (-not (Test-Path $full) -or (Get-Item $full).Length -le 0) {
    Write-Host "AUDIT INPUT MISSING/EMPTY: $f"
    exit 1
  }
}
foreach ($f in @("status.txt", "diff_stat.txt")) {
  $full = Join-Path $root (Join-Path $OUT $f)
  if (-not (Test-Path $full)) {
    Write-Host "AUDIT INPUT MISSING: $f"
    exit 1
  }
}
$headFile = ([System.IO.File]::ReadAllText((Join-Path $root (Join-Path $OUT "HEAD.txt")))).Trim()
$headLive = (& git rev-parse HEAD).Trim()
if ([string]::IsNullOrWhiteSpace($headFile) -or ($headFile -ne $headLive)) {
  Write-Host "AUDIT INPUT HEAD MISMATCH"
  exit 1
}

Write-Host "analyze_rc=$ANALYZE_RC test_rc=$TEST_RC"
if ($ANALYZE_RC -ne 0 -or $TEST_RC -ne 0) {
  Write-Host "VERIFY: FAILED"
  exit 1
}
Write-Host "VERIFY: OK"
