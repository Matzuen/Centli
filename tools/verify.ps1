# Windows PowerShell equivalent of tools/verify.sh
# Usage: powershell -File tools/verify.ps1
$ErrorActionPreference = "Continue"
$OUT = "docs/grokbot/audit_input"
New-Item -ItemType Directory -Force -Path $OUT | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$root = (Get-Location).Path
$startedUtc = [DateTime]::UtcNow.AddSeconds(-1)

function Write-Utf8([string]$RelPath, [string]$Text) {
  $full = Join-Path $root $RelPath
  [System.IO.File]::WriteAllText($full, $Text, $utf8)
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

# Freshness self-assert
$headFile = ([System.IO.File]::ReadAllText((Join-Path $root (Join-Path $OUT "HEAD.txt")))).Trim()
$headLive = (& git rev-parse HEAD).Trim()
if ($headFile -ne $headLive) {
  Write-Host "AUDIT INPUT STALE: HEAD.txt != git HEAD"
  exit 1
}

$analyzeTime = (Get-Item (Join-Path $OUT "analyze.txt")).LastWriteTimeUtc
$testTime = (Get-Item (Join-Path $OUT "test.txt")).LastWriteTimeUtc
if ($analyzeTime -lt $startedUtc -or $testTime -lt $startedUtc) {
  Write-Host "AUDIT INPUT STALE: analyze.txt/test.txt older than this verify run"
  exit 1
}

Write-Host "analyze_rc=$ANALYZE_RC test_rc=$TEST_RC"
if ($ANALYZE_RC -ne 0 -or $TEST_RC -ne 0) {
  Write-Host "VERIFY: FAILED"
  exit 1
}
Write-Host "VERIFY: OK"