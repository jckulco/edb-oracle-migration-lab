#!/usr/bin/env python3
"""Resincroniza secuencias e identidades después de una carga con IDs explícitos.

Se ejecuta automáticamente como parte de 09_after_load.sql, pero también puede
invocarse por separado cuando se recargan datos manualmente.
"""

from __future__ import annotations

import sys

from psycopg import sql

from . import pg_target
from .config import ConfigError, Settings, load_manifest


def resync(settings: Settings) -> int:
    manifest = load_manifest()
    conn = pg_target.connect(settings.edb, manifest.edb_schema)
    ajustes = 0
    try:
        with conn.cursor() as cur:
            for seq in manifest.sequences:
                cur.execute(
                    sql.SQL("SELECT COALESCE(MAX({col}), 0) FROM {schema}.{table}").format(
                        col=sql.Identifier(seq.column),
                        schema=sql.Identifier(manifest.edb_schema),
                        table=sql.Identifier(seq.table),
                    )
                )
                max_value = int(cur.fetchone()[0])
                cur.execute(
                    "SELECT setval(%s::regclass, %s, false)",
                    (seq.name, max_value + 1),
                )
                print(f"  {seq.name:<20} -> {max_value + 1}")
                ajustes += 1

            for ident in manifest.identity_columns:
                cur.execute(
                    "SELECT pg_get_serial_sequence(%s, %s)",
                    (f"{manifest.edb_schema}.{ident.table}", ident.column),
                )
                row = cur.fetchone()
                sequence_name = row[0] if row else None
                if not sequence_name:
                    print(
                        f"  AVISO: {ident.table}.{ident.column} no tiene secuencia de identidad",
                        file=sys.stderr,
                    )
                    continue
                cur.execute(
                    sql.SQL("SELECT COALESCE(MAX({col}), 0) FROM {schema}.{table}").format(
                        col=sql.Identifier(ident.column),
                        schema=sql.Identifier(manifest.edb_schema),
                        table=sql.Identifier(ident.table),
                    )
                )
                max_value = int(cur.fetchone()[0])
                cur.execute(
                    "SELECT setval(%s::regclass, %s, false)",
                    (sequence_name, max_value + 1),
                )
                print(f"  {ident.table}.{ident.column:<12} -> {max_value + 1}")
                ajustes += 1
        conn.commit()
    finally:
        conn.close()
    return ajustes


def main() -> int:
    try:
        settings = Settings.from_env()
    except (ConfigError, ValueError) as exc:
        print(f"ERROR de configuración: {exc}", file=sys.stderr)
        return 2

    print("Resincronizando secuencias e identidades...")
    try:
        total = resync(settings)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        return 3
    print(f"Secuencias ajustadas: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
