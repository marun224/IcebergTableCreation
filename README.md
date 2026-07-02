# NYC Yellow Taxi → Apache Iceberg on MinIO

Loads the 2024 NYC TLC yellow-taxi parquet files into an Apache Iceberg table,
using **PyIceberg** with a **REST catalog**, a **Postgres** metadata backend, and
**MinIO** (S3-compatible) for storage. The catalog is exposed on `localhost:8181`
so any notebook or process on this machine can read the tables.

## Architecture

```
input_data/*.parquet ──▶ load_data.py (PyIceberg) ──▶ Iceberg table
                                                          │
        ┌─────────────────────────────────────────────────┴───────────────┐
        ▼                              ▼                                    ▼
 Iceberg REST catalog          Postgres                                  MinIO
 (serves the API)        (durable catalog metadata:          (stores data + metadata files,
 http://localhost:8181    namespaces + table pointers)         bucket: s3://warehouse/)
```

- **MinIO** — object storage for the Iceberg warehouse (data + metadata). S3 API on `localhost:9100`, console on http://localhost:9101 (host ports 9100/9101 avoid clashing with any MinIO already on 9000/9001).
- **Postgres** — durable JDBC backend for the catalog. Holds namespace/table registrations so they **survive container restarts**. Without it, `tabulario/iceberg-rest` defaults to an in-memory catalog that forgets every table on restart.
- **Iceberg REST catalog** (`tabulario/iceberg-rest`) — serves the catalog API at http://localhost:8181.
- **pgAdmin4** — web UI for browsing the Postgres catalog tables directly, at http://localhost:8082 (dev convenience only; see [docs/OPERATIONS.md](docs/OPERATIONS.md)).
- **PyIceberg** — Python client that creates the table, writes the parquet data, and is how other notebooks connect.

Table: `nyc.yellow_tripdata`, partitioned by `month(tpep_pickup_datetime)`.

See [`docs/`](docs/) for deeper detail:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — components, data flow, and why each piece exists.
- [docs/CATALOG_ACCESS.md](docs/CATALOG_ACCESS.md) — **how to read these tables from a separate notebook or process.**
- [docs/OPERATIONS.md](docs/OPERATIONS.md) — start/stop, reset, and the migration note for the Postgres backend.

## Prerequisites

- Docker Desktop (running)
- Python 3.10+

## Quick start

```powershell
# 1. Create venv + install deps (also copies .env.example -> .env)
.\setup.ps1

# 2. Start Docker Desktop, then bring up the whole stack
#    (double-click start-stack.bat, or run:)
docker compose up -d

# 3. Create + load + verify the table
#    (double-click run-pipeline.bat, or run the three scripts below)
```

The two `.bat` helpers exist so the stack and pipeline can be launched with a
double-click, no terminal required:

| Script | What it does |
|--------|--------------|
| `start-stack.bat` | Waits for the Docker engine, runs `docker compose up -d`, prints status + catalog config |
| `run-pipeline.bat` | Runs `create_table.py` → `load_data.py` → `verify.py` in order |

To run the pipeline steps individually:

```powershell
docker compose up -d                       # MinIO + Postgres + REST catalog + bucket
.\.venv\Scripts\python.exe src\create_table.py
.\.venv\Scripts\python.exe src\load_data.py
.\.venv\Scripts\python.exe src\verify.py
```

Tear down (keep data + catalog volumes):

```powershell
docker compose down
```

Tear down and wipe **both** MinIO storage and the Postgres catalog:

```powershell
docker compose down -v
```

## Reading the tables from another notebook

The catalog is already exposed on `localhost:8181`. Any process on this machine
connects with the same PyIceberg config the project uses — full walkthrough in
[docs/CATALOG_ACCESS.md](docs/CATALOG_ACCESS.md). The short version:

```python
from pyiceberg.catalog import load_catalog

catalog = load_catalog("rest", **{
    "type": "rest",
    "uri": "http://localhost:8181",
    "s3.endpoint": "http://localhost:9100",
    "s3.access-key-id": "minioadmin",
    "s3.secret-access-key": "minioadmin",
    "s3.region": "us-east-1",
    "s3.path-style-access": "true",
})

df = catalog.load_table(("nyc", "yellow_tripdata")).scan(limit=5).to_pandas()
print(df)
```

## Project layout

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | MinIO, Postgres, bucket init (`mc`), Iceberg REST catalog |
| `.env` / `.env.example` | Credentials, endpoints, namespace/table names, Postgres login |
| `start-stack.bat` | Double-click to bring the Docker stack up |
| `run-pipeline.bat` | Double-click to run create → load → verify |
| `requirements.txt` | Python dependencies |
| `src/config.py` | Loads `.env`, builds the PyIceberg catalog |
| `src/create_table.py` | Creates namespace + partitioned Iceberg table |
| `src/load_data.py` | Reads parquet, conforms schema, appends to table |
| `src/verify.py` | Row count, partition count, sample query |
| `input_data/` | The 12 monthly parquet files |
| `docs/` | Architecture, catalog access, and operations docs |

## Notes

- Credentials default to `minioadmin` / `minioadmin` and the Postgres login to
  `iceberg` / `iceberg` (dev only — change in `.env`).
- The Postgres backend means table registrations persist across `docker compose
  restart` and `docker compose down` (without `-v`). The **first** time you switch
  to it, the catalog starts empty, so re-run `create_table.py` + `load_data.py`
  once to repopulate it (see [docs/OPERATIONS.md](docs/OPERATIONS.md)).
- `load_data.py` conforms each file to the table's exact schema before appending,
  so month-to-month column drift (name casing, int/float, string types) is handled.
- Re-running `create_table.py` is safe; it skips creation if the table exists.
  Re-running `load_data.py` will append the data **again** (duplicates) — drop/recreate
  the table first if you need a clean reload.
