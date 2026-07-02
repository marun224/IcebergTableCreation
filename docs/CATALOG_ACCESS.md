# Reading the tables from a separate notebook or process

The whole point of running a **REST catalog** is that more than one process can
read the tables. The catalog is already exposed on `http://localhost:8181` and
MinIO's S3 API on `http://localhost:9100`, so any notebook or script **on this
machine** can connect — no changes to the Docker stack are needed.

This guide covers same-machine access, which is the current setup.

## Prerequisites

- The stack is running (`docker compose ps` shows `iceberg-rest`, `minio`, and
  `postgres` up; `postgres` and `minio` healthy). Double-click `start-stack.bat`
  if not.
- Your notebook environment has PyIceberg and a query engine installed:

  ```
  pip install "pyiceberg[pyarrow,pandas]"
  ```

## Connect

Build a catalog handle with the same settings the project uses. The four things a
client needs are the **REST URI**, the **S3 endpoint**, the **credentials**, and
**path-style access** (required for MinIO):

```python
from pyiceberg.catalog import load_catalog

catalog = load_catalog("rest", **{
    "type": "rest",
    "uri": "http://localhost:8181",          # REST catalog
    "s3.endpoint": "http://localhost:9100",   # MinIO S3 API (host port)
    "s3.access-key-id": "minioadmin",
    "s3.secret-access-key": "minioadmin",
    "s3.region": "us-east-1",
    "s3.path-style-access": "true",
})
```

> Why `s3.endpoint` matters: the catalog hands back table metadata whose data
> lives in MinIO. PyIceberg then reads those files directly over S3, so the
> **client** must know where MinIO is. On this host that's `localhost:9100`.

## List and load

```python
# What namespaces / tables exist?
print(catalog.list_namespaces())          # e.g. [('nyc',)]
print(catalog.list_tables("nyc"))         # e.g. [('nyc', 'yellow_tripdata')]

# Load the table
table = catalog.load_table(("nyc", "yellow_tripdata"))
print(table.schema())
```

## Query

PyIceberg scans return Arrow, which converts to pandas, Polars, DuckDB, etc.

```python
import datetime as dt
from pyiceberg.expressions import And, GreaterThanOrEqual, LessThan

# A few rows, selected columns
df = table.scan(
    selected_fields=("tpep_pickup_datetime", "trip_distance", "total_amount"),
    limit=5,
).to_pandas()
print(df)

# Predicate + partition pruning (January 2024 pickups)
jan = table.scan(
    row_filter=And(
        GreaterThanOrEqual("tpep_pickup_datetime", dt.datetime(2024, 1, 1)),
        LessThan("tpep_pickup_datetime", dt.datetime(2024, 2, 1)),
    ),
).to_pandas()
print(len(jan))
```

### Query with DuckDB (fast local SQL)

```python
import duckdb

arrow_tbl = table.scan(
    selected_fields=("tpep_pickup_datetime", "total_amount"),
).to_arrow()

duckdb.sql("""
    SELECT date_trunc('month', tpep_pickup_datetime) AS mon,
           count(*) AS trips,
           round(avg(total_amount), 2) AS avg_fare
    FROM arrow_tbl
    GROUP BY 1 ORDER BY 1
""").show()
```

## Reuse the project's connection code

Instead of copying the config into every notebook, you can import the project's
existing helper. From a notebook whose working directory is the project root:

```python
import sys
sys.path.insert(0, "src")          # so `import config` resolves
from config import get_catalog, TABLE_IDENTIFIER

catalog = get_catalog()
table = catalog.load_table(TABLE_IDENTIFIER)
```

`src/config.py` reads `.env`, so the notebook picks up the same endpoints and
credentials automatically.

## Writing from another process

Everything above is read-oriented, but the catalog is fully read/write: a second
process can append or create tables too. Two callers writing to the **same**
table should coordinate — Iceberg commits are atomic, but a losing concurrent
commit will need a retry. For independent tables there's nothing to coordinate.

## Credentials verified: it is live

`GET http://localhost:8181/v1/config` returning JSON (e.g.
`{"defaults":{},"overrides":{}}`) confirms the catalog API is reachable. If a
notebook can hit that URL, it can connect with the config above.

## Beyond this machine (not the current setup)

If you later need notebooks on **other containers** or **other machines**, the
two things that change are the hostnames clients use (`iceberg-rest:8181` /
`minio:9000` on the compose network, or the host's LAN IP from another machine)
and making sure those addresses resolve for the client. Ask and we can extend the
compose file and docs for that case.
