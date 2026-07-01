"""Verify the loaded Iceberg table: total rows, partitions, and a sample query."""
from __future__ import annotations

import datetime as dt

from pyiceberg.expressions import And, GreaterThanOrEqual, LessThan

from config import TABLE_IDENTIFIER, get_catalog


def main() -> None:
    catalog = get_catalog()
    tbl = catalog.load_table(TABLE_IDENTIFIER)

    # Total record count from the current snapshot summary (cheap, no full scan).
    snap = tbl.current_snapshot()
    if snap is None:
        print("Table has no snapshots yet — nothing loaded.")
        return
    total = snap.summary.get("total-records", "?")
    print(f"Total records: {int(total):,}" if str(total).isdigit() else f"Total records: {total}")

    # Partitions present.
    parts = tbl.inspect.partitions().to_pydict()
    n_parts = len(parts.get("record_count", []))
    print(f"Partitions: {n_parts}")

    # Sample scan: January 2024 pickups, a few columns, first rows.
    jan = tbl.scan(
        row_filter=And(
            GreaterThanOrEqual("tpep_pickup_datetime", dt.datetime(2024, 1, 1)),
            LessThan("tpep_pickup_datetime", dt.datetime(2024, 2, 1)),
        ),
        selected_fields=("tpep_pickup_datetime", "trip_distance", "total_amount"),
        limit=5,
    ).to_arrow()
    print("\nSample (Jan 2024):")
    print(jan.to_pandas().to_string(index=False))


if __name__ == "__main__":
    main()
