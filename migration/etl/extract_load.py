#!/usr/bin/env python3
"""Carga las tablas del manifiesto desde Oracle hacia EPAS.

Características:
  * python-oracledb thin: no hace falta Oracle Instant Client.
  * COPY FROM STDIN para un rendimiento razonable.
  * Normalización explícita de tipos (JSON, XML, arrays, LOB, timestamps).
  * Orden topológico para respetar claves foráneas cuando ya existen.
  * Reintentable: con --truncate limpia el destino antes de cargar.
  * Reporte JSON en migration/reports/data_load.json.

Uso:
  python -m migration.etl.extract_load
  python -m migration.etl.extract_load --truncate
  python -m migration.etl.extract_load --tables clientes,pedidos --dry-run
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import UTC, datetime
from pathlib import Path

from . import oracle_source, pg_target
from .config import ConfigError, Manifest, Settings, TableSpec, load_manifest
from .type_mapping import normalize_value, type_family


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--tables",
        help="Lista separada por comas. Por defecto carga todas las tablas.",
    )
    parser.add_argument(
        "--truncate",
        action="store_true",
        help="Vacía las tablas destino antes de cargar (RESTART IDENTITY).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Solo cuenta filas en origen y destino, sin escribir.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=0,
        help="Filas por fetch de Oracle (por defecto ETL_BATCH_SIZE).",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Ruta del reporte JSON (por defecto reports/data_load.json).",
    )
    return parser.parse_args()


def select_tables(manifest: Manifest, raw: str | None) -> list[TableSpec]:
    if not raw:
        return list(manifest.tables)
    requested = [name.strip() for name in raw.split(",") if name.strip()]
    known = set(manifest.table_names)
    unknown = [name for name in requested if name not in known]
    if unknown:
        raise ConfigError(f"Tablas desconocidas: {', '.join(unknown)}")
    by_name = {t.name: t for t in manifest.tables}
    return [by_name[name] for name in requested]


def normalized_rows(
    conn,
    spec: TableSpec,
    types: dict[str, tuple[str, str]],
    batch_size: int,
    stats: dict[str, int],
):
    for row in oracle_source.fetch_rows(conn, spec, batch_size):
        stats["rows_read"] += 1
        yield tuple(
            normalize_value(value, *types[column])
            for column, value in zip(spec.columns, row, strict=True)
        )


def load_table(
    oracle_conn,
    edb_conn,
    manifest: Manifest,
    spec: TableSpec,
    batch_size: int,
) -> dict:
    started = time.perf_counter()
    types = pg_target.column_types(edb_conn, manifest.edb_schema, spec.name, spec.columns)
    stats = {"rows_read": 0}
    rows = normalized_rows(oracle_conn, spec, types, batch_size, stats)

    families = [type_family(*types[column]) for column in spec.columns]
    loaded = pg_target.copy_rows(
        edb_conn, manifest.edb_schema, spec.name, spec.columns, rows, families
    )
    edb_conn.commit()
    elapsed = time.perf_counter() - started

    return {
        "table": spec.name,
        "rows_read": stats["rows_read"],
        "rows_loaded": loaded,
        "seconds": round(elapsed, 3),
        "columns": len(spec.columns),
    }


def main() -> int:
    args = parse_args()
    try:
        settings = Settings.from_env()
        manifest = load_manifest()
        tables = select_tables(manifest, args.tables)
    except (ConfigError, ValueError) as exc:
        print(f"ERROR de configuración: {exc}", file=sys.stderr)
        return 2

    batch_size = args.batch_size or settings.batch_size
    report_path = args.report or settings.report_dir / "data_load.json"
    started_at = datetime.now(UTC)

    print(f"Origen : Oracle {settings.oracle.dsn} (schema {manifest.oracle_schema})")
    print(f"Destino: EPAS {settings.edb.host}:{settings.edb.port}/{settings.edb.dbname} "
          f"(schema {manifest.edb_schema})")
    print(f"Tablas : {', '.join(t.name for t in tables)}")
    print("-" * 78)

    try:
        oracle_conn = oracle_source.connect(settings.oracle, manifest.oracle_schema)
        edb_conn = pg_target.connect(settings.edb, manifest.edb_schema)
    except Exception as exc:  # noqa: BLE001 - error de conexión reportado al usuario
        print(f"ERROR de conexión: {exc}", file=sys.stderr)
        return 3

    results: list[dict] = []
    try:
        if args.dry_run:
            for spec in tables:
                source_count = oracle_source.count_rows(oracle_conn, spec)
                target_count = pg_target.count_rows(
                    edb_conn, manifest.edb_schema, spec.name
                )
                print(f"  {spec.name:<24} origen={source_count:>8}  destino={target_count:>8}")
                results.append(
                    {
                        "table": spec.name,
                        "source_rows": source_count,
                        "target_rows": target_count,
                        "dry_run": True,
                    }
                )
        else:
            if args.truncate:
                print("Limpiando tablas destino...")
                pg_target.truncate(edb_conn, manifest.edb_schema, [t.name for t in tables])
                edb_conn.commit()

            for spec in tables:
                print(f"Cargando {spec.name}...", end=" ", flush=True)
                result = load_table(oracle_conn, edb_conn, manifest, spec, batch_size)
                results.append(result)
                print(
                    f"{result['rows_loaded']} filas en {result['seconds']:.2f}s",
                    flush=True,
                )
    except Exception as exc:  # noqa: BLE001 - se reporta y se hace rollback
        edb_conn.rollback()
        print(f"\nERROR durante la carga: {exc}", file=sys.stderr)
        return 4
    finally:
        oracle_conn.close()
        edb_conn.close()

    report = {
        "generated_at": started_at.isoformat(),
        "oracle_dsn": settings.oracle.dsn,
        "oracle_schema": manifest.oracle_schema,
        "edb_schema": manifest.edb_schema,
        "dry_run": args.dry_run,
        "tables": results,
        "total_rows": sum(r.get("rows_loaded", 0) for r in results),
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print("-" * 78)
    print(f"Reporte: {report_path}")
    if not args.dry_run:
        print(f"Total cargado: {report['total_rows']} filas")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
