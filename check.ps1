# Read-only: shows the current table row count, partitions and a sample.
Set-Location $PSScriptRoot
try {
    & ".\.venv\Scripts\python.exe" src\verify.py
} catch {
    Write-Host "CHECK FAILED: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host "`nPress Enter to close..."
Read-Host
