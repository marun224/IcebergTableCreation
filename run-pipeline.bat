@echo off
title Iceberg pipeline (create -> load -> verify)
cd /d "D:\workspace\IcebergTableCreation"

echo ============================================================
echo  create_table.py  (namespace + partitioned table)
echo ============================================================
.\.venv\Scripts\python.exe src\create_table.py
echo.

echo ============================================================
echo  load_data.py  (read parquet, conform schema, append)
echo ============================================================
.\.venv\Scripts\python.exe src\load_data.py
echo.

echo ============================================================
echo  verify.py  (row count, partitions, sample query)
echo ============================================================
.\.venv\Scripts\python.exe src\verify.py
echo.

echo Pipeline complete. This window can be closed.
pause
