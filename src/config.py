"""Central config: loads .env and builds the PyIceberg REST catalog."""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from pyiceberg.catalog import load_catalog
from pyiceberg.catalog.rest import RestCatalog

# Project root = parent of this src/ directory.
ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")


def _env(key: str, default: str | None = None) -> str:
    val = os.getenv(key, default)
    if val is None:
        raise RuntimeError(f"Missing required environment variable: {key}")
    return val


AWS_ACCESS_KEY_ID = _env("AWS_ACCESS_KEY_ID", "minioadmin")
AWS_SECRET_ACCESS_KEY = _env("AWS_SECRET_ACCESS_KEY", "minioadmin")
AWS_REGION = _env("AWS_REGION", "us-east-1")
WAREHOUSE_BUCKET = _env("WAREHOUSE_BUCKET", "warehouse")
REST_URI = _env("REST_URI", "http://localhost:8181")
S3_ENDPOINT = _env("S3_ENDPOINT", "http://localhost:9000")
NAMESPACE = _env("ICEBERG_NAMESPACE", "nyc")
TABLE_NAME = _env("ICEBERG_TABLE", "yellow_tripdata")
INPUT_DIR = ROOT / _env("INPUT_DIR", "input_data")

TABLE_IDENTIFIER = (NAMESPACE, TABLE_NAME)


def get_catalog() -> RestCatalog:
    """Return a PyIceberg catalog bound to the local REST catalog + MinIO."""
    return load_catalog(
        "rest",
        **{
            "type": "rest",
            "uri": REST_URI,
            "s3.endpoint": S3_ENDPOINT,
            "s3.access-key-id": AWS_ACCESS_KEY_ID,
            "s3.secret-access-key": AWS_SECRET_ACCESS_KEY,
            "s3.region": AWS_REGION,
            "s3.path-style-access": "true",
        },
    )
