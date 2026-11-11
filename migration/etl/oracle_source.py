"""Acceso al origen Oracle con python-oracledb en modo thin."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import oracledb

from .config import OracleSettings, TableSpec


class OracleSourceError(RuntimeError):
    pass


def connect(settings: OracleSettings, schema: str | None = None):
    """Abre una conexión thin (sin Oracle Instant Client)."""
    # Los LOB se materializan como str/bytes y los NUMBER como Decimal.
    oracledb.defaults.fetch_lobs = False
    oracledb.defaults.fetch_decimals = True

    try:
        conn = oracledb.connect(
            user=settings.user,
            password=settings.password,
            dsn=settings.dsn,
        )
    except oracledb.Error as exc:
        raise OracleSourceError(
            f"No se pudo conectar a Oracle ({settings.dsn}): {exc}"
        ) from exc

    if schema:
        conn.current_schema = schema.upper()
    with conn.cursor() as cur:
        cur.execute("ALTER SESSION SET TIME_ZONE = 'UTC'")
    return conn


def fetch_rows(
    conn,
    spec: TableSpec,
    batch_size: int = 1000,
) -> Iterator[tuple[Any, ...]]:
    """Itera filas del SELECT del manifiesto sin cargar todo en memoria."""
    with conn.cursor() as cur:
        cur.arraysize = batch_size
        cur.execute(spec.select)
        while True:
            rows = cur.fetchmany(batch_size)
            if not rows:
                break
            yield from rows


def fetch_all(conn, spec: TableSpec, batch_size: int = 1000) -> list[tuple[Any, ...]]:
    return list(fetch_rows(conn, spec, batch_size))


def scalar(conn, sql: str, params: dict | None = None) -> Any:
    with conn.cursor() as cur:
        cur.execute(sql, params or {})
        row = cur.fetchone()
        return None if row is None else row[0]


def count_rows(conn, spec: TableSpec) -> int:
    return int(scalar(conn, f"SELECT COUNT(*) FROM ({spec.select}) t") or 0)


def version(conn) -> str:
    """Devuelve la versión de Oracle con una consulta portable entre versiones."""
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT version_full FROM product_component_version "
                "WHERE product LIKE 'Oracle Database%' FETCH FIRST 1 ROW ONLY"
            )
            row = cur.fetchone()
            if row and row[0]:
                return str(row[0])
    except oracledb.Error:
        pass
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT banner FROM v$version "
                "WHERE banner LIKE 'Oracle Database%' FETCH FIRST 1 ROW ONLY"
            )
            row = cur.fetchone()
            return str(row[0]) if row else "desconocida"
    except oracledb.Error:
        return "desconocida"
