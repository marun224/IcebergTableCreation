@echo off
title Iceberg status check (verify only - read only)
cd /d "D:\workspace\IcebergTableCreation"
echo Running verify.py (read-only)...
echo.
.\.venv\Scripts\python.exe src\verify.py
echo.
echo ----- exit code: %errorlevel% -----
pause
