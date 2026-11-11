#!/usr/bin/env python3
"""Valida la migración comparando Oracle y EPAS fila a fila.

Para cada tabla del manifiesto:
  * Cuenta filas y nulos por columna.
  * Calcula un SHA-256 canónico por fila (independiente del motor).
  * Compara las claves primarias y reporta diferencias por columna.
  * Ejecuta pruebas funcionales de paquetes, funciones y vistas.

Salida:
  migration/reports/validation.md
  migration/reports/validation.json

Código de salida: 0 si todo pasa, 1 si hay diferencias.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from . import functional, oracle_source, pg_target
from .config import ConfigError, Manifest, Settings, TableSpec, load_manifest
from .type_mapping import canonical_value, normalize_value, row_digest, type_family


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tables", help="Lista separada por comas")
    parser.add_argument("--skip-functional", action="store_true")
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def selected_tables(manifest: Manifest, raw: str | None) -> list[TableSpec]:
    if not raw:
        return list(manifest.tables)
    requested = [n.strip() for n in raw.split(",") if n.strip()]
    by_name = {t.name: t for t in manifest.tables}
    missing = [n for n in requested if n not in by_name]
    if missing:
        raise ConfigError(f"Tablas desconocidas: {', '.join(missing)}")
    return [by_name[n] for n in requested]


def prepare_rows(
    rows: list[tuple[Any, ...]],
    spec: TableSpec,
    types: dict[str, tuple[str, str]],
) -> list[tuple[Any, ...]]:
    normalized = []
    for row in rows:
        normalized.append(
            tuple(
                normalize_value(value, *types[column])
                for column, value in zip(spec.columns, row, strict=True)
            )
        )
    return normalized


def compare_table(
    oracle_conn,
    edb_conn,
    manifest: Manifest,
    spec: TableSpec,
) -> dict[str, Any]:
    types = pg_target.column_types(edb_conn, manifest.edb_schema, spec.name, spec.columns)
    families = [type_family(*types[column]) for column in spec.columns]
    pk_idx = [spec.columns.index(c) for c in spec.pk]

    source_rows = prepare_rows(
        oracle_source.fetch_all(oracle_conn, spec), spec, types
    )
    target_rows = list(
        pg_target.fetch_rows(edb_conn, manifest.edb_schema, spec.name, spec.columns)
    )

    def key_of(row: tuple[Any, ...]) -> tuple[str, ...]:
        return tuple(canonical_value(row[i], families[i]) for i in pk_idx)

    source = {key_of(row): row for row in source_rows}
    target = {key_of(row): row for row in target_rows}
    source_dupes = len(source_rows) - len(source)
    target_dupes = len(target_rows) - len(target)

    result: dict[str, Any] = {
        "table": spec.name,
        "source_rows": len(source_rows),
        "target_rows": len(target_rows),
        "source_duplicate_pks": source_dupes,
        "target_duplicate_pks": target_dupes,
        "ok": False,
        "missing_in_target": [],
        "extra_in_target": [],
        "row_differences": [],
        "null_mismatches": [],
    }

    if len(source_rows) != len(target_rows):
        result["error"] = "Los conteos de filas no coinciden"
        return result
    if source_dupes or target_dupes:
        result["error"] = "Hay claves primarias duplicadas en el conjunto de datos"
        return result

    missing = sorted(set(source) - set(target))
    extra = sorted(set(target) - set(source))
    result["missing_in_target"] = [list(k) for k in missing[:20]]
    result["extra_in_target"] = [list(k) for k in extra[:20]]

    for idx, column in enumerate(spec.columns):
        source_nulls = sum(1 for row in source_rows if row[idx] is None)
        target_nulls = sum(1 for row in target_rows if row[idx] is None)
        if source_nulls != target_nulls:
            result["null_mismatches"].append(
                {
                    "column": column,
                    "source_nulls": source_nulls,
                    "target_nulls": target_nulls,
                }
            )

    differences: list[dict[str, Any]] = []
    for key in sorted(set(source) & set(target)):
        source_row = source[key]
        target_row = target[key]
        if row_digest(source_row, families) == row_digest(target_row, families):
            continue
        columns = []
        for idx, column in enumerate(spec.columns):
            sv = canonical_value(source_row[idx], families[idx])
            tv = canonical_value(target_row[idx], families[idx])
            if sv != tv:
                columns.append(
                    {
                        "column": column,
                        "source": sv[:200],
                        "target": tv[:200],
                    }
                )
        differences.append({"pk": list(key), "columns": columns[:10]})
        if len(differences) >= 10:
            break

    result["row_differences"] = differences
    result["ok"] = not missing and not extra and not differences and not result["null_mismatches"]
    if not result["ok"]:
        result["error"] = "Diferencias de datos"
    return result


def build_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Validación de la migración Oracle -> EPAS",
        "",
        f"- **Generado:** {report['generated_at']}",
        f"- **Resultado global:** {'OK' if report['ok'] else 'FALLO'}",
        f"- **Tablas validadas:** {len(report['tables'])}",
        f"- **Pruebas funcionales:** "
        f"{report['functional']['passed']}/{report['functional']['total']} OK",
        "",
        "## Datos por tabla",
        "",
        "| Tabla | Origen | Destino | Checksum | Estado |",
        "|---|---:|---:|---|---|",
    ]
    for table in report["tables"]:
        status = "OK" if table["ok"] else "FALLO"
        lines.append(
            f"| `{table['table']}` | {table['source_rows']:,} | "
            f"{table['target_rows']:,} | {'sí' if table['ok'] else 'no'} | {status} |"
        )
    lines.append("")

    failed = [t for t in report["tables"] if not t["ok"]]
    if failed:
        lines.append("## Detalle de fallos")
        lines.append("")
        for table in failed:
            lines.append(f"### `{table['table']}`")
            if table.get("error"):
                lines.append("")
                lines.append(f"- Error: {table['error']}")
            if table["missing_in_target"]:
                lines.append(f"- Faltan en destino: {table['missing_in_target']}")
            if table["extra_in_target"]:
                lines.append(f"- Sobran en destino: {table['extra_in_target']}")
            for diff in table["row_differences"]:
                lines.append(f"- PK {diff['pk']}:")
                for col in diff["columns"]:
                    lines.append(
                        f"  - `{col['column']}`: origen=`{col['source']}` "
                        f"destino=`{col['target']}`"
                    )
            for null_diff in table["null_mismatches"]:
                lines.append(
                    f"- Nulos en `{null_diff['column']}`: "
                    f"origen={null_diff['source_nulls']} "
                    f"destino={null_diff['target_nulls']}"
                )
            lines.append("")

    lines.append("## Pruebas funcionales")
    lines.append("")
    lines.append("| Prueba | Origen | Destino | Esperado | Estado |")
    lines.append("|---|---|---|---|---|")
    for test in report["functional"]["results"]:
        status = "OK" if test["ok"] else "FALLO"
        lines.append(
            f"| `{test['id']}` | `{test.get('oracle', '')}` | "
            f"`{test.get('edb', '')}` | `{test.get('expected') or ''}` | {status} |"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    try:
        settings = Settings.from_env()
        manifest = load_manifest()
        tables = selected_tables(manifest, args.tables)
    except (ConfigError, ValueError) as exc:
        print(f"ERROR de configuración: {exc}", file=sys.stderr)
        return 2

    report_path = args.report or settings.report_dir / "validation.json"
    started = datetime.now(UTC)
    print(f"Validando {len(tables)} tablas...")

    try:
        oracle_conn = oracle_source.connect(settings.oracle, manifest.oracle_schema)
        edb_conn = pg_target.connect(settings.edb, manifest.edb_schema)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR de conexión: {exc}", file=sys.stderr)
        return 3

    table_results: list[dict[str, Any]] = []
    try:
        for spec in tables:
            print(f"  {spec.name:<24}", end=" ", flush=True)
            result = compare_table(oracle_conn, edb_conn, manifest, spec)
            table_results.append(result)
            print("OK" if result["ok"] else "FALLO", flush=True)
    finally:
        oracle_conn.close()
        edb_conn.close()

    functional_results: list[dict[str, Any]] = []
    if not args.skip_functional:
        print("Ejecutando pruebas funcionales...")
        try:
            functional_results = functional.run_tests(settings)
        except Exception as exc:  # noqa: BLE001
            print(f"ERROR en pruebas funcionales: {exc}", file=sys.stderr)
            functional_results = [
                {
                    "id": "ejecucion",
                    "ok": False,
                    "error": str(exc),
                }
            ]
        functional.print_summary(functional_results)

    passed = sum(1 for r in functional_results if r["ok"])
    report = {
        "generated_at": started.isoformat(),
        "ok": all(t["ok"] for t in table_results)
        and (args.skip_functional or passed == len(functional_results)),
        "tables": table_results,
        "functional": {
            "total": len(functional_results),
            "passed": passed,
            "results": functional_results,
        },
    }

    report_path.parent.mkdir(parents=True, exist_ok=True)
    json_path = report_path
    md_path = report_path.with_suffix(".md")
    json_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    md_path.write_text(build_markdown(report) + "\n", encoding="utf-8")

    print("-" * 78)
    print(f"Reporte: {md_path}")
    print(f"JSON:    {json_path}")
    print(f"Resultado global: {'OK' if report['ok'] else 'FALLO'}")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
