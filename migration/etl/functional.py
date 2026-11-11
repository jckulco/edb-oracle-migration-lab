"""Pruebas funcionales no destructivas Oracle vs EPAS."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

from . import oracle_source, pg_target
from .config import Settings, load_test_specs
from .type_mapping import decimal_canonical


def canonical_scalar(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, Decimal):
        return decimal_canonical(value)
    if isinstance(value, float):
        return format(value, ".10g")
    if isinstance(value, datetime):
        return value.isoformat(sep=" ", timespec="microseconds")
    if isinstance(value, date):
        return value.isoformat()
    return str(value)


def _fetch_scalar(conn, sql_text: str) -> Any:
    with conn.cursor() as cur:
        cur.execute(sql_text)
        row = cur.fetchone()
        return None if row is None else row[0]


def run_tests(settings: Settings) -> list[dict[str, Any]]:
    tests = load_test_specs()
    oracle_conn = oracle_source.connect(settings.oracle)
    edb_conn = pg_target.connect(settings.edb)
    results: list[dict[str, Any]] = []

    try:
        for test in tests:
            test_id = str(test.get("id", "sin_id"))
            entry: dict[str, Any] = {
                "id": test_id,
                "description": test.get("description", ""),
                "oracle_sql": test.get("oracle"),
                "edb_sql": test.get("edb"),
                "ok": False,
            }
            try:
                oracle_value = _fetch_scalar(oracle_conn, str(test["oracle"]))
                edb_value = _fetch_scalar(edb_conn, str(test["edb"]))
                oracle_canonical = canonical_scalar(oracle_value)
                edb_canonical = canonical_scalar(edb_value)
                expected = test.get("expected")
                expected_canonical = (
                    canonical_scalar(expected) if expected is not None else None
                )
                matches = oracle_canonical == edb_canonical
                expected_ok = (
                    expected_canonical is None
                    or (
                        oracle_canonical == expected_canonical
                        and edb_canonical == expected_canonical
                    )
                )
                entry.update(
                    {
                        "oracle": oracle_canonical,
                        "edb": edb_canonical,
                        "expected": expected_canonical,
                        "matches": matches,
                        "expected_ok": expected_ok,
                        "ok": matches and expected_ok,
                    }
                )
            except Exception as exc:  # noqa: BLE001 - se reporta el fallo de la prueba
                entry["error"] = str(exc)
            results.append(entry)
    finally:
        oracle_conn.close()
        edb_conn.close()
    return results


def print_summary(results: list[dict[str, Any]]) -> None:
    passed = sum(1 for r in results if r["ok"])
    print(f"Pruebas funcionales: {passed}/{len(results)} OK")
    for result in results:
        if result["ok"]:
            continue
        detail = result.get("error") or (
            f"oracle={result.get('oracle')!r} edb={result.get('edb')!r} "
            f"expected={result.get('expected')!r}"
        )
        print(f"  FALLO {result['id']}: {detail}")
