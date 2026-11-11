"""Mapeo y normalización de tipos Oracle -> EPAS.

Este módulo no se conecta a ninguna base de datos: es lógica pura y se prueba
con pytest. Se usa tanto en la carga (normalize_value) como en la validación
(canonical_value + row_digest).
"""

from __future__ import annotations

import hashlib
import json
import xml.etree.ElementTree as ET
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal, InvalidOperation
from typing import Any

# Tabla de referencia que también se muestra en la documentación.
ORACLE_TO_EPAS: dict[str, str] = {
    "NUMBER(p,s)": "numeric(p,s)",
    "NUMBER(p)": "numeric(p) / bigint si es un identificador",
    "INTEGER": "integer / bigint",
    "BINARY_FLOAT": "real",
    "BINARY_DOUBLE": "double precision",
    "VARCHAR2(n)": "varchar(n)",
    "NVARCHAR2(n)": "varchar(n) (UTF-8)",
    "CHAR(n)": "char(n)",
    "CLOB / NCLOB": "text",
    "BLOB": "bytea",
    "RAW(n)": "bytea",
    "LONG": "text",
    "DATE (con hora)": "timestamp(0)",
    "TIMESTAMP(n)": "timestamp(n)",
    "TIMESTAMP WITH TIME ZONE": "timestamptz",
    "TIMESTAMP WITH LOCAL TIME ZONE": "timestamptz (normalizado a UTC)",
    "INTERVAL YEAR TO MONTH": "interval (o columnas years/months)",
    "INTERVAL DAY TO SECOND": "interval day to second",
    "XMLTYPE": "xml",
    "JSON (23ai)": "jsonb",
    "BOOLEAN (23ai)": "boolean",
    "ROWID / UROWID": "sin equivalente directo (usar PK)",
    "SYS_REFCURSOR": "refcursor",
    "OBJECT TYPE": "columnas planas / composite / jsonb",
    "NESTED TABLE": "text[] / tabla hija / jsonb",
    "VARRAY": "text[] / jsonb",
}


def type_family(data_type: str | None, udt_name: str | None = None) -> str:
    """Clasifica un tipo de information_schema en una familia normalizada."""
    dt = (data_type or "").lower().strip()
    udt = (udt_name or "").lower().strip()

    if dt == "array" or udt.startswith("_"):
        return "array"
    if dt in {"json", "jsonb"} or udt in {"json", "jsonb"}:
        return "json"
    if dt == "xml" or udt == "xml":
        return "xml"
    if dt == "bytea" or udt == "bytea":
        return "bytea"
    if "with time zone" in dt or udt == "timestamptz":
        return "timestamptz"
    if "without time zone" in dt or udt == "timestamp":
        return "timestamp"
    if dt == "date" or udt == "date":
        return "date"
    if dt == "interval" or udt == "interval":
        return "interval"
    if dt in {"bigint", "integer", "smallint"} or udt in {"int8", "int4", "int2"}:
        return "integer"
    if dt in {"numeric", "decimal"} or udt == "numeric":
        return "numeric"
    if dt == "real" or udt == "float4":
        return "real"
    if dt == "double precision" or udt == "float8":
        return "double"
    if dt == "boolean" or udt == "bool":
        return "boolean"
    return "text"


def split_array(value: Any) -> list[str] | None:
    """Convierte el LISTAGG('a|b') de Oracle en un arreglo de texto."""
    if value is None:
        return None
    if isinstance(value, (list, tuple)):
        return [str(v) for v in value]
    if isinstance(value, str):
        return value.split("|") if value else []
    raise TypeError(f"Valor de arreglo no soportado: {type(value)!r}")


def normalize_value(value: Any, data_type: str | None, udt_name: str | None) -> Any:
    """Convierte un valor Oracle/EPAS al tipo Python que psycopg espera."""
    if value is None:
        return None

    family = type_family(data_type, udt_name)

    if family == "array":
        return split_array(value)

    if family == "json":
        if isinstance(value, (dict, list)):
            return value
        if isinstance(value, bytes):
            value = value.decode("utf-8")
        try:
            return json.loads(value)
        except (TypeError, json.JSONDecodeError) as exc:
            raise ValueError(f"JSON inválido: {value!r}") from exc

    if family == "bytea":
        if isinstance(value, bytes):
            return value
        if isinstance(value, memoryview):
            return bytes(value)
        if isinstance(value, str):
            text = value[2:] if value.startswith("\\x") else value
            return bytes.fromhex(text)
        raise TypeError(f"Valor binario no soportado: {type(value)!r}")

    if family == "timestamptz":
        if isinstance(value, str):
            value = datetime.fromisoformat(value)
        if isinstance(value, date) and not isinstance(value, datetime):
            value = datetime.combine(value, datetime.min.time())
        if not isinstance(value, datetime):
            raise TypeError(f"Timestamp no soportado: {type(value)!r}")
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)

    if family in {"timestamp", "date"}:
        if isinstance(value, datetime):
            return value
        if isinstance(value, date):
            return datetime.combine(value, datetime.min.time())
        if isinstance(value, str):
            return datetime.fromisoformat(value)
        raise TypeError(f"Fecha no soportada: {type(value)!r}")

    if family == "interval":
        if isinstance(value, timedelta):
            return value
        if isinstance(value, str):
            # Formato ISO 8601 de PostgreSQL, por ejemplo P1DT2H.
            return value
        raise TypeError(f"Intervalo no soportado: {type(value)!r}")

    if family == "integer":
        return int(value)

    if family == "numeric":
        if isinstance(value, Decimal):
            return value
        try:
            return Decimal(str(value))
        except InvalidOperation as exc:
            raise ValueError(f"Número inválido: {value!r}") from exc

    if family in {"real", "double"}:
        return float(value)

    if family == "boolean":
        if isinstance(value, str):
            return value.strip().lower() in {"1", "true", "t", "s", "y", "yes"}
        return bool(value)

    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def decimal_canonical(value: Decimal) -> str:
    """Representación estable: sin notación científica ni ceros finales."""
    if value == 0:
        return "0"
    normalized = value.normalize()
    try:
        return format(normalized, "f")
    except ValueError:
        return str(normalized)


def canonical_value(value: Any, family: str) -> str:
    """Representación estable para comparar/hashear entre motores."""
    if value is None:
        return "\\N"

    if family == "integer":
        return str(int(value))
    if family == "numeric":
        if not isinstance(value, Decimal):
            value = Decimal(str(value))
        return decimal_canonical(value)
    if family in {"real", "double"}:
        number = float(value)
        if number == 0:
            return "0"
        if number != number:  # NaN
            return "nan"
        if number in {float("inf"), float("-inf")}:
            return str(number)
        return format(number, ".10g")
    if family == "boolean":
        return "1" if bool(value) else "0"
    if family == "timestamptz":
        if isinstance(value, str):
            value = datetime.fromisoformat(value)
        if isinstance(value, datetime) and value.tzinfo is None:
            value = value.replace(tzinfo=UTC)
        return value.astimezone(UTC).isoformat(timespec="microseconds")
    if family == "timestamp":
        if isinstance(value, date) and not isinstance(value, datetime):
            value = datetime.combine(value, datetime.min.time())
        return value.isoformat(sep=" ", timespec="microseconds")
    if family == "date":
        return value.isoformat()
    if family == "interval":
        if isinstance(value, timedelta):
            return f"{value.total_seconds():.6f}"
        return str(value)
    if family == "bytea":
        if isinstance(value, memoryview):
            value = bytes(value)
        return bytes(value).hex()
    if family == "array":
        if value is None:
            return "\\N"
        items = value if isinstance(value, (list, tuple)) else split_array(value)
        return json.dumps([str(item) for item in items], ensure_ascii=False)
    if family == "json":
        if isinstance(value, str):
            value = json.loads(value)
        return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    if family == "xml":
        text = str(value)
        try:
            return ET.canonicalize(text, strip_text=True)
        except ET.ParseError:
            return text.strip()
    return str(value)


def row_digest(values: tuple[Any, ...] | list[Any], families: list[str]) -> str:
    """Hash SHA-256 de una fila canónica, independiente del motor."""
    digest = hashlib.sha256()
    for value, family in zip(values, families, strict=True):
        encoded = canonical_value(value, family).encode("utf-8")
        digest.update(len(encoded).to_bytes(4, "big"))
        digest.update(encoded)
    return digest.hexdigest()
