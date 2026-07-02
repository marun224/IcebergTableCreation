# Operations runbook

Day-to-day commands for running, resetting, and troubleshooting the stack.
All commands run from the project root with Docker Desktop running.

## Start / stop

```powershell
# Bring everything up (MinIO + Postgres + REST catalog + pgAdmin + bucket init)
docker compose up -d            # or double-click start-stack.bat

# Check status — postgres and minio should be "healthy", iceberg-rest/pgadmin "Up"
docker compose ps

# Confirm the catalog API is live
curl http://localhost:8181/v1/config

# Stop containers, keep all data (MinIO storage + Postgres catalog)
docker compose down

# Stop AND wipe both volumes (full reset — see below)
docker compose down -v
```

## The two `.bat` helpers

Because typing into a terminal isn't always convenient, two double-clickable
scripts live in the project root:

- **`start-stack.bat`** — waits for the Docker engine, runs `docker compose up -d`,
  then prints `docker compose ps` and the catalog config.
- **`run-pipeline.bat`** — runs `create_table.py` → `load_data.py` → `verify.py`
  against the venv in order.

## First-time migration to the Postgres backend

The catalog now uses a **persistent Postgres** backend instead of the image's
default in-memory SQLite. The first time you switch to it, the catalog store
starts **empty** — it has no record of any table created under the old in-memory
catalog (even though the data files may still sit in MinIO).

To repopulate, run the pipeline once:

```powershell
.\.venv\Scripts\python.exe src\create_table.py
.\.venv\Scripts\python.exe src\load_data.py
.\.venv\Scripts\python.exe src\verify.py
```

After this, registrations persist across restarts — you won't need to repeat it
unless you wipe the `postgres-data` volume.

## Volumes

| Volume | Holds | Wiped by |
|--------|-------|----------|
| `minio-data` | Table data + Iceberg metadata files | `docker compose down -v` |
| `postgres-data` | Catalog metadata (namespaces, table pointers) | `docker compose down -v` |
| `pgadmin-data` | pgAdmin's own login/saved-server settings (not catalog data) | `docker compose down -v` |

`docker compose down -v` removes **all three**, so the catalog and the storage
stay in sync (`pgadmin-data` wiping just means re-adding the server connection
from the pgAdmin section above). Removing only `minio-data` or only
`postgres-data` would leave the catalog pointing at missing data, or orphaned
data with no catalog entry — avoid partial wipes of those two.

## Clean reload of the table

`load_data.py` **appends**, so re-running it duplicates rows. For a clean reload,
drop and recreate the table first:

```python
from config import get_catalog, TABLE_IDENTIFIER
get_catalog().drop_table(TABLE_IDENTIFIER)   # then re-run create_table + load_data
```

Or do a full reset with `docker compose down -v && docker compose up -d`, then
run the pipeline.

## Inspecting storage directly

Open the MinIO console at http://localhost:9101 (login: `minioadmin` /
`minioadmin`) to browse the `warehouse` bucket — you'll see `nyc/yellow_tripdata/`
with `data/` and `metadata/` folders.

## Browsing the Postgres catalog tables

`postgres` holds the raw JDBC catalog tables Iceberg's `JdbcCatalog` writes to
(the namespace/table registrations backing the REST catalog API). To browse
them directly instead of going through PyIceberg:

1. Open pgAdmin4 at http://localhost:8082 and log in with
   `admin@local.dev` / `admin` (dev-only default, see `docker-compose.yml`).
2. Add a server (first time only): right-click **Servers → Register → Server**.
   - **General → Name**: anything, e.g. `iceberg-catalog`
   - **Connection → Host**: `postgres` (the compose network hostname, not
     `localhost`) · **Port**: `5432` · **Maintenance DB** / **Username**:
     `iceberg` · **Password**: `iceberg` (from `.env`'s `POSTGRES_DB` /
     `POSTGRES_USER` / `POSTGRES_PASSWORD`)
   - pgAdmin remembers this connection across restarts (`pgadmin-data` volume).
3. Navigate **Servers → iceberg-catalog → Databases → iceberg → Schemas →
   public → Tables**. Iceberg's `JdbcCatalog` auto-creates `iceberg_tables`
   (namespace/table → current metadata-file pointer) and
   `iceberg_namespace_properties` — right-click either and **View/Edit Data →
   All Rows** to see the catalog contents.

## Troubleshooting

**`docker compose up` hangs on "waiting for postgres to be healthy"**
Postgres is still initializing its data directory on first run. Give it 10–20s;
`docker compose ps` will flip it to `healthy`.

**REST catalog returns errors right after startup**
`iceberg-rest` waits for Postgres to be healthy, but the API needs a couple of
extra seconds after the container starts. Retry `curl http://localhost:8181/v1/config`.

**A notebook can't find a table that "should" exist**
Most likely the catalog was reset (empty Postgres) but the data was never
reloaded. Run the pipeline (see migration section). Confirm with
`catalog.list_tables("nyc")`.

**Port already in use**
Host ports are `8181` (catalog), `9100`/`9101` (MinIO), `8082` (pgAdmin). If
something else owns them, change the left side of the `ports:` mappings in
`docker-compose.yml`.

## Logs

```powershell
docker compose logs iceberg-rest
docker compose logs postgres
docker compose logs minio
docker compose logs pgadmin
docker compose logs -f iceberg-rest   # follow
```
