"""Acceso al destino EDB Postgres Advanced Server con psycopg 3."""

from __future__ import annotations

from collections.abc import Iterable, Iterator, Sequence
from typing import Any

import psycopg
from psycopg import sql
from psycopg.types.json import Jsonb

from .config import EdbSettings


class EdbTargetError(RuntimeError):
    pass


def connect(settings: EdbSettings, schema: str = "ventas"):
    try:
        conn = psycopg.connect(
            host=settings.host,
            port=settings.port,
            dbname=settings.dbname,
            user=settings.user,
            password=settings.password,
            sslmode=settings.sslmode,
            autocommit=False,
        )
    except psycopg.Error as exc:
        raise EdbTargetError(
            f"No se pudo conectar a EPAS ({settings.host}:{settings.port}/"
            f"{settings.dbname}): {exc}"
        ) from exc

    with conn.cursor() as cur:
        cur.execute(
            sql.SQL("SET search_path TO {}, public").format(sql.Identifier(schema))
        )
        cur.execute("SET TIME ZONE 'UTC'")
    return conn


def get_columns(conn, schema: str, table: str) -> list[dict[str, str]]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT column_name, data_type, udt_name
              FROM information_schema.columns
             WHERE table_schema = %s
               AND table_name = %s
             ORDER BY ordinal_position
            """,
            (schema, table),
        )
        return [
            {"name": row[0], "data_type": row[1], "udt_name": row[2]}
            for row in cur.fetchall()
        ]


def column_types(
    conn, schema: str, table: str, columns: Sequence[str]
) -> dict[str, tuple[str, str]]:
    """Devuelve {columna: (data_type, udt_name)} y valida que existan."""
    available = {c["name"]: (c["data_type"], c["udt_name"]) for c in get_columns(conn, schema, table)}
    missing = [c for c in columns if c not in available]
    if missing:
        raise EdbTargetError(
            f"La tabla {schema}.{table} no tiene las columnas: {', '.join(missing)}"
        )
    return {c: available[c] for c in columns}


def copy_rows(
    conn,
    schema: str,
    table: str,
    columns: Sequence[str],
    rows: Iterable[Sequence[Any]],
    families: Sequence[str] | None = None,
) -> int:
    """Carga filas con COPY FROM STDIN. Devuelve el número de filas enviadas.

    Para JSONB se envuelve el dict/lista en Jsonb; psycopg no siempre adapta
    dict de forma implícita en COPY. El resto de tipos usa los adaptadores
    nativos (Decimal, datetime, timedelta, bytes, listas).
    """
    columns_sql = sql.SQL(", ").join(sql.Identifier(c) for c in columns)
    statement = sql.SQL("COPY {}.{} ({}) FROM STDIN").format(
        sql.Identifier(schema), sql.Identifier(table), columns_sql
    )
    count = 0
    with conn.cursor() as cur:
        with cur.copy(statement) as copy:
            for row in rows:
                if families:
                    row = tuple(
                        Jsonb(value)
                        if family == "json" and isinstance(value, (dict, list))
                        else value
                        for value, family in zip(row, families, strict=True)
                    )
                copy.write_row(row)
                count += 1
    return count


def truncate(conn, schema: str, tables: Sequence[str]) -> None:
    if not tables:
        return
    targets = sql.SQL(", ").join(
        sql.SQL("{}.{}").format(sql.Identifier(schema), sql.Identifier(t))
        for t in tables
    )
    with conn.cursor() as cur:
        cur.execute(sql.SQL("TRUNCATE TABLE {} RESTART IDENTITY").format(targets))


def fetch_rows(
    conn, schema: str, table: str, columns: Sequence[str]
) -> Iterator[tuple[Any, ...]]:
    columns_sql = sql.SQL(", ").join(sql.Identifier(c) for c in columns)
    statement = sql.SQL("SELECT {} FROM {}.{}").format(
        columns_sql, sql.Identifier(schema), sql.Identifier(table)
    )
    with conn.cursor() as cur:
        cur.execute(statement)
        yield from cur.fetchall()


def count_rows(conn, schema: str, table: str) -> int:
    with conn.cursor() as cur:
        cur.execute(
            sql.SQL("SELECT COUNT(*) FROM {}.{}").format(
                sql.Identifier(schema), sql.Identifier(table)
            )
        )
        return int(cur.fetchone()[0])


def scalar(conn, statement: str | sql.Composable, params: Sequence[Any] | None = None) -> Any:
    with conn.cursor() as cur:
        cur.execute(statement, params)
        row = cur.fetchone()
        return None if row is None else row[0]


def server_version(conn) -> str:
    with conn.cursor() as cur:
        cur.execute("SHOW server_version")
        return str(cur.fetchone()[0])


def sequence_exists(conn, schema: str, name: str) -> bool:
    return bool(
        scalar(
            conn,
            """
            SELECT EXISTS (
              SELECT 1
                FROM information_schema.sequences
               WHERE sequence_schema = %s AND sequence_name = %s
            )
            """,
            (schema, name),
        )
    )
