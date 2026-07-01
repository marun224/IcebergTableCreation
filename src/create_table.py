"""Create the Iceberg namespace and the yellow_tripdata table.

Schema mirrors the NYC TLC yellow-taxi parquet columns. The table is
partitioned by month(tpep_pickup_datetime), matching the monthly source files.
Idempotent: safe to re-run (skips creation if the table already exists).
"""
from __future__ import annotations

from pyiceberg.partitioning import PartitionField, PartitionSpec
from pyiceberg.schema import Schema
from pyiceberg.transforms import MonthTransform
from pyiceberg.types import (
    DoubleType,
    IntegerType,
    LongType,
    NestedField,
    StringType,
    TimestampType,
)

from config import NAMESPACE, TABLE_IDENTIFIER, get_catalog

# Field ids are stable and explicit. required=False because TLC data contains nulls.
SCHEMA = Schema(
    NestedField(1, "VendorID", IntegerType(), required=False),
    NestedField(2, "tpep_pickup_datetime", TimestampType(), required=False),
    NestedField(3, "tpep_dropoff_datetime", TimestampType(), required=False),
    NestedField(4, "passenger_count", LongType(), required=False),
    NestedField(5, "trip_distance", DoubleType(), required=False),
    NestedField(6, "RatecodeID", LongType(), required=False),
    NestedField(7, "store_and_fwd_flag", StringType(), required=False),
    NestedField(8, "PULocationID", IntegerType(), required=False),
    NestedField(9, "DOLocationID", IntegerType(), required=False),
    NestedField(10, "payment_type", LongType(), required=False),
    NestedField(11, "fare_amount", DoubleType(), required=False),
    NestedField(12, "extra", DoubleType(), required=False),
    NestedField(13, "mta_tax", DoubleType(), required=False),
    NestedField(14, "tip_amount", DoubleType(), required=False),
    NestedField(15, "tolls_amount", DoubleType(), required=False),
    NestedField(16, "improvement_surcharge", DoubleType(), required=False),
    NestedField(17, "total_amount", DoubleType(), required=False),
    NestedField(18, "congestion_surcharge", DoubleType(), required=False),
    NestedField(19, "Airport_fee", DoubleType(), required=False),
)

# Partition by month of pickup. source_id=2 -> tpep_pickup_datetime.
PARTITION_SPEC = PartitionSpec(
    PartitionField(source_id=2, field_id=1000, transform=MonthTransform(), name="pickup_month")
)


def main() -> None:
    catalog = get_catalog()

    if catalog.namespace_exists(NAMESPACE):
        print(f"Namespace '{NAMESPACE}' already exists.")
    else:
        catalog.create_namespace(NAMESPACE)
        print(f"Created namespace '{NAMESPACE}'.")

    if catalog.table_exists(TABLE_IDENTIFIER):
        print(f"Table {'.'.join(TABLE_IDENTIFIER)} already exists; leaving as-is.")
    else:
        catalog.create_table(
            identifier=TABLE_IDENTIFIER,
            schema=SCHEMA,
            partition_spec=PARTITION_SPEC,
            properties={"write.parquet.compression-codec": "zstd"},
        )
        print(f"Created table {'.'.join(TABLE_IDENTIFIER)} (partitioned by month(tpep_pickup_datetime)).")


if __name__ == "__main__":
    main()
