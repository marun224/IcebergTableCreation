# Full clean slate: tears down any previous containers/volumes from earlier
# attempts, brings up a fresh isolated stack, then creates + loads + verifies.
# Does NOT touch any pre-existing 'minio' container you run yourself.
Set-Location $PSScriptRoot
$py = ".\.venv\Scripts\python.exe"

Write-Host "Cleaning up previous state (this will not affect your own MinIO)..." -ForegroundColor Cyan
# The default project name derived from this folder, in case an earlier run created it:
docker compose -p icebergtablecreation down -v --remove-orphans 2>$null
# The isolated project defined in docker-compose.yml (name: iceberg-nyc):
docker compose down -v --remove-orphans 2>$null
# Leftover fixed-name containers from the very first compose version (NOT 'minio'):
docker rm -f iceberg-rest mc 2>$null | Out-Null

$ErrorActionPreference = "Stop"
try {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw "Docker is not running. Start Docker Desktop and retry." }

    Write-Host "Starting fresh MinIO + Iceberg REST catalog..." -ForegroundColor Cyan
    docker compose up -d

    Write-Host "Waiting for the REST catalog to become ready..." -ForegroundColor Cyan
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8181/v1/config" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch { Start-Sleep -Seconds 2 }
    }
    if (-not $ready) { throw "REST catalog did not become ready. Check 'docker compose logs iceberg-rest'." }
    Write-Host "REST catalog is up." -ForegroundColor Green

    Write-Host "`n[1/3] Creating Iceberg table..." -ForegroundColor Cyan
    & $py src\create_table.py
    if ($LASTEXITCODE -ne 0) { throw "create_table.py failed (exit $LASTEXITCODE)." }

    Write-Host "`n[2/3] Loading parquet files..." -ForegroundColor Cyan
    & $py src\load_data.py
    if ($LASTEXITCODE -ne 0) { throw "load_data.py failed (exit $LASTEXITCODE)." }

    Write-Host "`n[3/3] Verifying..." -ForegroundColor Cyan
    & $py src\verify.py
    if ($LASTEXITCODE -ne 0) { throw "verify.py failed (exit $LASTEXITCODE)." }

    Write-Host "`nDONE. MinIO console: http://localhost:9101 (minioadmin/minioadmin)" -ForegroundColor Green
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host "`nPress Enter to close..."
    Read-Host
}
