# NYC Yellow Taxi → Apache Iceberg on MinIO

Loads the 2024 NYC TLC yellow-taxi parquet files into an Apache Iceberg table,
using **PyIceberg** with a **REST catalog** and **MinIO** (S3-compatible) for storage.

## Architecture

```
input_data/*.parquet ──▶ load_data.py (PyIceberg) ──▶ Iceberg table
                                                          │
                          ┌───────────────────────────────┴───────────────┐
                          ▼                                                ▼
                Iceberg REST catalog                                    MinIO
                (tracks metadata pointers)              (stores data + metadata files,
                 http://localhost:8181                   bucket: s3://warehouse/)
```

- **MinIO** — object storage for the Iceberg warehouse (data + metadata). Console: http://localhost:9101 (host ports 9100/9101 to avoid clashing with any MinIO already on 9000/9001)
- **Iceberg REST catalog** (`tabulario/iceberg-rest`) — tracks table metadata. API: http://localhost:8181
- **PyIceberg** — Python client that creates the table and writes the parquet data.

Table: `nyc.yellow_tripdata`, partitioned by `month(tpep_pickup_datetime)`.

## Prerequisites

- Docker Desktop (running)
- Python 3.10+

## Quick start

```powershell
# 1. Create venv + install deps (also copies .env.example -> .env)
.\setup.ps1

# 2. Start Docker Desktop, then bring up infra + create/load/verify the table
.\run.ps1
```

That runs the three steps below in order. To run them individually:

```powershell
docker compose up -d                 # MinIO + REST catalog + bucket
.\.venv\Scripts\python.exe src\create_table.py
.\.venv\Scripts\python.exe src\load_data.py
.\.venv\Scripts\python.exe src\verify.py
```

Tear down (keep data volume):

```powershell
docker compose down
```

Tear down and wipe MinIO storage:

```powershell
docker compose down -v
```

## Project layout

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | MinIO, bucket init (`mc`), Iceberg REST catalog |
| `.env` / `.env.example` | Credentials, endpoints, namespace/table names |
| `requirements.txt` | Python dependencies |
| `src/config.py` | Loads `.env`, builds the PyIceberg catalog |
| `src/create_table.py` | Creates namespace + partitioned Iceberg table |
| `src/load_data.py` | Reads parquet, conforms schema, appends to table |
| `src/verify.py` | Row count, partition count, sample query |
| `input_data/` | The 12 monthly parquet files |

## Notes

- Credentials default to `minioadmin` / `minioadmin` (dev only — change in `.env`).
- `load_data.py` conforms each file to the table's exact schema before appending,
  so month-to-month column drift (name casing, int/float, string types) is handled.
- Re-running `create_table.py` is safe; it skips creation if the table exists.
  Re-running `load_data.py` will append the data **again** (duplicates) — drop/recreate
  the table first if you need a clean reload.
