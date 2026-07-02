# Architecture

This project stores NYC yellow-taxi trip data as an **Apache Iceberg** table and
exposes it through a **REST catalog** so multiple processes can read it. Four
containers plus a Python client make up the system.

## Components

```
                          ┌──────────────────────────┐
   PyIceberg client       │   iceberg-rest (:8181)    │
   (create_table.py,      │   tabulario/iceberg-rest  │
    load_data.py,   ─────▶│   serves the catalog API  │
    verify.py, and        └───────────┬──────────────┘
    any notebook)                     │
        │                             │ JDBC
        │ S3 (data + metadata)        ▼
        │                    ┌──────────────────┐
        │                    │  postgres (:5432) │
        │                    │  catalog metadata │
        ▼                    │  (namespaces,     │
   ┌──────────────┐          │   table pointers) │
   │ minio (:9100) │         └──────────────────┘
   │ S3 warehouse  │
   │ s3://warehouse│
   └──────────────┘
```

### iceberg-rest — the catalog API

`tabulario/iceberg-rest` implements the Iceberg REST catalog spec. Clients talk
to it over HTTP at `http://localhost:8181`. It does **not** store table data; it
tracks *where* each table's current metadata file lives and answers questions
like "list namespaces," "load table `nyc.yellow_tripdata`," and "commit a new
snapshot."

Its container-side config points S3 operations at `http://minio:9000` (the
compose-network hostname) and its metadata store at Postgres.

### postgres — durable catalog metadata

This is the change that makes the catalog **persistent**. By default the
`tabulario/iceberg-rest` image uses an in-memory SQLite catalog: every namespace
and table registration lives only in the container's RAM and is lost on restart
(the data files survive in MinIO, but the catalog forgets they exist).

Pointing the catalog at a Postgres JDBC backend moves that state into a database
with its own Docker volume (`postgres-data`), so registrations survive
`docker compose restart` and `docker compose down`. Relevant `iceberg-rest`
environment:

```
CATALOG_CATALOG__IMPL=org.apache.iceberg.jdbc.JdbcCatalog
CATALOG_URI=jdbc:postgresql://postgres:5432/${POSTGRES_DB}
CATALOG_JDBC_USER=${POSTGRES_USER}
CATALOG_JDBC_PASSWORD=${POSTGRES_PASSWORD}
```

Postgres holds only *metadata pointers* — small rows. The actual table data and
Iceberg metadata files all live in MinIO.

### minio — the S3 warehouse

MinIO is S3-compatible object storage. It holds the Iceberg **warehouse**: the
parquet data files and the Iceberg metadata files (manifests, manifest lists,
snapshots), all under `s3://warehouse/`. Host ports are `9100` (S3 API) and
`9101` (web console) to avoid clashing with any MinIO already running on the
default 9000/9001.

### mc — one-shot bucket init

A short-lived `minio/mc` container that waits for MinIO, creates the `warehouse`
bucket if missing, and exits. It runs as part of `docker compose up`.

### PyIceberg client

The Python scripts (and any external notebook) use PyIceberg to talk to the REST
catalog for metadata and directly to MinIO over S3 for data. `src/config.py`
builds the catalog handle from `.env`.

## Data flow: loading a table

1. `create_table.py` asks the REST catalog to create the `nyc` namespace and the
   `yellow_tripdata` table. The catalog writes the initial metadata file to MinIO
   and records the pointer in Postgres.
2. `load_data.py` reads each monthly parquet file, conforms it to the table
   schema, and appends it. PyIceberg writes new data + metadata files to MinIO,
   then commits the new snapshot pointer through the REST catalog (which updates
   Postgres).
3. `verify.py` loads the table through the catalog and runs a sample scan,
   reading data files straight from MinIO.

## Why a REST catalog (vs. a local SQLite/Hadoop catalog)

A REST catalog is a **network service**, so several independent processes —
this project's loader plus any number of separate notebooks — can share one
consistent view of the tables at the same time. A file-based catalog would tie
the metadata to one process's local filesystem and wouldn't be safely shareable.

## Endpoints summary

| Service | Host address | Container address | Purpose |
|---------|--------------|-------------------|---------|
| REST catalog | `http://localhost:8181` | `iceberg-rest:8181` | Catalog API |
| MinIO S3 | `http://localhost:9100` | `minio:9000` | Data + metadata storage |
| MinIO console | `http://localhost:9101` | `minio:9001` | Web UI |
| Postgres | (not published) | `postgres:5432` | Catalog metadata (internal only) |

Postgres is intentionally **not** published to the host — only `iceberg-rest`
needs it, over the compose network.
