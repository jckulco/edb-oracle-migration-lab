#!/usr/bin/env python3
"""Benchmark indicativo de consultas equivalentes en Oracle y EPAS.

No es una prueba científica: el objetivo es mostrar cómo comparar planes y
tiempos, no declarar un ganador. Ejecuta una fase de calentamiento y reporta
la mediana de varias iteraciones.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from . import oracle_source, pg_target
from .config import ConfigError, Settings, load_benchmark_specs


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iterations", type=int, default=5)
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def time_query_oracle(conn, sql_text: str, iterations: int) -> float:
    with conn.cursor() as cur:
        cur.execute(sql_text)  # calentamiento
        cur.fetchall()
        samples = []
        for _ in range(iterations):
            started = time.perf_counter()
            cur.execute(sql_text)
            cur.fetchall()
            samples.append((time.perf_counter() - started) * 1000)
    return statistics.median(samples)


def time_query_edb(conn, sql_text: str, iterations: int) -> float:
    with conn.cursor() as cur:
        cur.execute(sql_text)
        cur.fetchall()
        samples = []
        for _ in range(iterations):
            started = time.perf_counter()
            cur.execute(sql_text)
            cur.fetchall()
            samples.append((time.perf_counter() - started) * 1000)
        conn.rollback()
    return statistics.median(samples)


def build_markdown(results: list[dict[str, Any]], iterations: int) -> str:
    lines = [
        "# Benchmark indicativo Oracle vs EPAS",
        "",
        f"- **Iteraciones por consulta:** {iterations} (más calentamiento)",
        f"- **Generado:** {datetime.now(UTC).isoformat()}",
        "",
        "| Consulta | Oracle (ms) | EPAS (ms) | Diferencia |",
        "|---|---:|---:|---:|",
    ]
    for r in results:
        if "error" in r:
            lines.append(f"| `{r['id']}` | error | error | - |")
            continue
        delta = r["edb_ms"] - r["oracle_ms"]
        pct = (delta / r["oracle_ms"] * 100) if r["oracle_ms"] else 0
        lines.append(
            f"| `{r['id']}` | {r['oracle_ms']:.2f} | {r['edb_ms']:.2f} | "
            f"{delta:+.2f} ms ({pct:+.1f}%) |"
        )
    lines.extend(
        [
            "",
            "> Los tiempos dependen de la máquina, Docker, caché, estadísticas y "
            "del plan elegido. Úsalos para detectar regresiones gruesas, no para "
            "comparar productos.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    try:
        settings = Settings.from_env()
        queries = load_benchmark_specs()
    except (ConfigError, ValueError) as exc:
        print(f"ERROR de configuración: {exc}", file=sys.stderr)
        return 2

    report_path = args.report or settings.report_dir / "benchmark.json"
    oracle_conn = oracle_source.connect(settings.oracle)
    edb_conn = pg_target.connect(settings.edb)
    results: list[dict[str, Any]] = []
    try:
        for spec in queries:
            query_id = str(spec.get("id", "consulta"))
            print(f"  {query_id}...", end=" ", flush=True)
            try:
                oracle_ms = time_query_oracle(
                    oracle_conn, str(spec["oracle"]), args.iterations
                )
                edb_ms = time_query_edb(edb_conn, str(spec["edb"]), args.iterations)
                results.append(
                    {
                        "id": query_id,
                        "description": spec.get("description", ""),
                        "oracle_ms": oracle_ms,
                        "edb_ms": edb_ms,
                    }
                )
                print(f"Oracle={oracle_ms:.2f} ms  EPAS={edb_ms:.2f} ms")
            except Exception as exc:  # noqa: BLE001
                print("ERROR")
                results.append({"id": query_id, "error": str(exc)})
    finally:
        oracle_conn.close()
        edb_conn.close()

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "generated_at": datetime.now(UTC).isoformat(),
        "iterations": args.iterations,
        "results": results,
    }
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    md_path = report_path.with_suffix(".md")
    md_path.write_text(build_markdown(results, args.iterations) + "\n", encoding="utf-8")
    print(f"Reporte: {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
