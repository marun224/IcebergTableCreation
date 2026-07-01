# Brings up MinIO + Iceberg REST catalog, then creates the table, loads the
# parquet files, and verifies. Requires Docker Desktop running and .\setup.ps1
# already done.  Usage:  .\run.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

try {
    $py = ".\.venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { throw "Virtual env not found. Run .\setup.ps1 first." }

    # Confirm Docker is available.
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw "Docker is not running. Start Docker Desktop and retry." }

    Write-Host "Starting MinIO + Iceberg REST catalog (pulling images on first run)..." -ForegroundColor Cyan
    docker compose up -d

    Write-Host "Waiting for the REST catalog to become ready..." -ForegroundColor Cyan
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8181/v1/config" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch { Start-Sleep -Seconds 2 }
    }
    if (-not $ready) { throw "REST catalog did not become ready in time. Check 'docker compose logs iceberg-rest'." }
    Write-Host "REST catalog is up." -ForegroundColor Green

    Write-Host "`n[1/3] Creating Iceberg table..." -ForegroundColor Cyan
    & $py src\create_table.py

    Write-Host "`n[2/3] Loading parquet files..." -ForegroundColor Cyan
    & $py src\load_data.py

    Write-Host "`n[3/3] Verifying..." -ForegroundColor Cyan
    & $py src\verify.py

    Write-Host "`nAll done. MinIO console: http://localhost:9101 (minioadmin/minioadmin)" -ForegroundColor Green
}
catch {
    Write-Host "`nRUN FAILED: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host "`nPress Enter to close..."
    Read-Host
}
