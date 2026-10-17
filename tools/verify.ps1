# Windows PowerShell equivalent of tools/verify.sh
# Usage: pwsh -File tools/verify.ps1
Continue = "Continue"
 = "docs/grokbot/audit_input"
New-Item -ItemType Directory -Force -Path  | Out-Null

Write-Host "== analyze =="
flutter analyze 2>&1 | Tee-Object -FilePath "/analyze.txt"
 = 
Get-Content "/analyze.txt"

Write-Host "== test =="
flutter test 2>&1 | Tee-Object -FilePath "/test.txt"
 = 
Get-Content "/test.txt" | Select-Object -Last 5

Write-Host "analyze_rc= test_rc="
if ( -ne 0 -or  -ne 0) {
  Write-Host "VERIFY: FAILED"
  exit 1
}
Write-Host "VERIFY: OK"
