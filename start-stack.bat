@echo off
title Iceberg stack startup
cd /d "D:\workspace\IcebergTableCreation"

echo Waiting for the Docker engine to be ready...
:waitloop
docker info >nul 2>&1
if errorlevel 1 (
  timeout /t 3 >nul
  echo   ...still waiting for Docker Desktop to start...
  goto waitloop
)

echo.
echo Docker is ready. Bringing up the stack (minio + postgres + iceberg-rest + bucket init)...
echo.
docker compose up -d

echo.
echo ===== docker compose ps =====
docker compose ps

echo.
echo ===== REST catalog config (http://localhost:8181/v1/config) =====
timeout /t 5 >nul
curl -s http://localhost:8181/v1/config
echo.
echo.
echo Done. This window can be closed.
pause
