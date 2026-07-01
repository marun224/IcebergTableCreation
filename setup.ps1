# Creates a Python virtual environment and installs dependencies.
# Run once from the project folder:  .\setup.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Find a working Python launcher: prefer the 'py' launcher, fall back to 'python'.
function Get-PythonCmd {
    foreach ($c in @(@("py","-3"), @("python"), @("python3"))) {
        try {
            & $c[0] @($c[1..($c.Length-1)]) --version *> $null
            if ($LASTEXITCODE -eq 0) { return $c }
        } catch { }
    }
    return $null
}

try {
    $pycmd = Get-PythonCmd
    if ($null -eq $pycmd) {
        throw "No Python found on PATH. Install Python 3.10+ or ensure 'py'/'python' is available."
    }
    Write-Host ("Using Python: " + ($pycmd -join ' ')) -ForegroundColor DarkGray

    if (-not (Test-Path ".venv")) {
        Write-Host "Creating virtual environment (.venv)..." -ForegroundColor Cyan
        & $pycmd[0] @($pycmd[1..($pycmd.Length-1)]) -m venv .venv
    }

    $venvPy = ".\.venv\Scripts\python.exe"
    Write-Host "Upgrading pip..." -ForegroundColor Cyan
    & $venvPy -m pip install --upgrade pip
    Write-Host "Installing dependencies..." -ForegroundColor Cyan
    & $venvPy -m pip install -r requirements.txt

    if (-not (Test-Path ".env")) {
        Copy-Item ".env.example" ".env"
        Write-Host "Created .env from .env.example" -ForegroundColor Yellow
    }

    Write-Host "`nSetup complete. Next: start Docker Desktop, then run .\run.ps1" -ForegroundColor Green
}
catch {
    Write-Host "`nSETUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host "`nPress Enter to close..."
    Read-Host
}
