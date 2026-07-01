"""Read every parquet in INPUT_DIR and append it to the Iceberg table.

Each file is conformed to the table's exact Arrow schema before appending,
so any column drift across months (name casing, int vs float, string vs
large_string) is handled defensively. Files are appended one at a time so a
failure is isolated and the load can be restarted.
"""
from __future__ import annotations

import sys

import pyarrow as pa
import pyarrow.parquet as pq

from config import INPUT_DIR, TABLE_IDENTIFIER, get_catalog


def conform_to_schema(table: pa.Table, target: pa.Schema) -> pa.Table:
    """Return a table whose columns exactly match `target` (order, names, types).

    Missing columns are filled with nulls; extras are dropped; types are cast.
    """
    arrays = []
    for field in target:
        if field.name in table.column_names:
            col = table.column(field.name)
            if not col.type.equals(field.type):
                col = col.cast(field.type, safe=False)
            arrays.append(col)
        else:
            arrays.append(pa.nulls(table.num_rows, type=field.type))
    return pa.Table.from_arrays(arrays, schema=target)


def main() -> None:
    files = sorted(INPUT_DIR.glob("*.parquet"))
    if not files:
        sys.exit(f"No parquet files found in {INPUT_DIR}")

    catalog = get_catalog()
    tbl = catalog.load_table(TABLE_IDENTIFIER)
    target = tbl.schema().as_arrow()

    grand_total = 0
    for path in files:
        arrow_tbl = pq.read_table(path)
        conformed = conform_to_schema(arrow_tbl, target)
        tbl.append(conformed)
        grand_total += conformed.num_rows
        print(f"  appended {path.name:<32} {conformed.num_rows:>10,} rows")

    print(f"\nDone. Appended {len(files)} files, {grand_total:,} rows total.")


if __name__ == "__main__":
    main()
