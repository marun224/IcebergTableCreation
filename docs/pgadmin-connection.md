# pgAdmin → Postgres Catalog Connection

How to inspect the Iceberg JDBC catalog backend via pgAdmin.

## Access pgAdmin

- URL: http://localhost:8082
- Login: `admin@local.dev` / `admin`

(Both set in `docker-compose.yml` under the `pgadmin` service.)

## Register the Postgres server

Right-click **Servers → Register → Server…**, then:

| Field | Value |
|---|---|
| Name (General tab) | Iceberg Catalog |
| Host name/address (Connection tab) | `postgres` |
| Port | `5432` |
| Maintenance database | `iceberg` |
| Username | `iceberg` |
| Password | `iceberg` |
| Save password? | on |

Host is `postgres` (the compose service name) because pgAdmin talks to it over the
`iceberg_net` Docker network, not via a host port. Credentials come from `.env`
(`POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB`, all `iceberg`).

## Query the catalog

Open **Tools → Query Tool** on the `iceberg` database. The Iceberg `JdbcCatalog`
maintains two tables:

- `iceberg_tables` — namespace/table pointers + current metadata location
- `iceberg_namespace_properties` — namespace-level properties

```sql
SELECT catalog_name, table_namespace, table_name, metadata_location
FROM iceberg_tables
ORDER BY table_namespace, table_name;
```

Expected row (after loading the NYC data):

| catalog_name | table_namespace | table_name | metadata_location |
|---|---|---|---|
| rest_backend | nyc | yellow_tripdata | s3://warehouse/nyc/yellow_tripdata/metadata/00012-…json |

A row here confirms the table is persisted in Postgres rather than the ephemeral
SQLite catalog the REST image would otherwise use.
