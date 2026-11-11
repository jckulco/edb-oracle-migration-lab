from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest

from migration.etl.type_mapping import (
    ORACLE_TO_EPAS,
    canonical_value,
    decimal_canonical,
    normalize_value,
    row_digest,
    split_array,
    type_family,
)


@pytest.mark.parametrize(
    ("data_type", "udt_name", "expected"),
    [
        ("bigint", "int8", "integer"),
        ("numeric", "numeric", "numeric"),
        ("character varying", "varchar", "text"),
        ("timestamp without time zone", "timestamp", "timestamp"),
        ("timestamp with time zone", "timestamptz", "timestamptz"),
        ("date", "date", "date"),
        ("interval", "interval", "interval"),
        ("jsonb", "jsonb", "json"),
        ("xml", "xml", "xml"),
        ("bytea", "bytea", "bytea"),
        ("ARRAY", "_text", "array"),
        ("boolean", "bool", "boolean"),
        ("real", "float4", "real"),
        ("double precision", "float8", "double"),
        ("text", "text", "text"),
    ],
)
def test_type_family(data_type, udt_name, expected):
    assert type_family(data_type, udt_name) == expected


def test_oracle_to_epas_reference_is_not_empty():
    assert ORACLE_TO_EPAS["CLOB / NCLOB"] == "text"
    assert ORACLE_TO_EPAS["XMLTYPE"] == "xml"


def test_split_array():
    assert split_array("555|777") == ["555", "777"]
    assert split_array("") == []
    assert split_array(None) is None


def test_normalize_json_and_array():
    assert normalize_value('{"b": 1, "a": 2}', "jsonb", "jsonb") == {"b": 1, "a": 2}
    assert normalize_value("555|777", "ARRAY", "_text") == ["555", "777"]


def test_normalize_timestamptz_naive_to_utc():
    value = datetime(2025, 1, 2, 3, 4, 5)
    result = normalize_value(value, "timestamp with time zone", "timestamptz")
    assert result.tzinfo == UTC
    assert result.hour == 3


def test_normalize_bytea():
    assert normalize_value(b"\x01\x02", "bytea", "bytea") == b"\x01\x02"
    assert normalize_value("\\x0102", "bytea", "bytea") == b"\x01\x02"


def test_normalize_numeric_to_decimal():
    assert normalize_value("12.30", "numeric", "numeric") == Decimal("12.30")
    assert normalize_value(12, "bigint", "int8") == 12


def test_canonical_numeric_ignores_scale():
    assert canonical_value(Decimal("1.20"), "numeric") == "1.2"
    assert canonical_value(Decimal("1000"), "numeric") == "1000"
    assert canonical_value(Decimal("0.00"), "numeric") == "0"


def test_decimal_canonical():
    assert decimal_canonical(Decimal("1.2300")) == "1.23"
    assert decimal_canonical(Decimal("-0.00")) == "0"


def test_canonical_json_is_order_independent():
    assert canonical_value({"b": 2, "a": 1}, "json") == canonical_value(
        {"a": 1, "b": 2}, "json"
    )


def test_canonical_datetime_and_interval():
    aware = datetime(2025, 1, 1, 12, 0, tzinfo=UTC)
    assert canonical_value(aware, "timestamptz").startswith("2025-01-01T12:00:00")
    assert canonical_value(timedelta(hours=1, seconds=30), "interval") == "3630.000000"


def test_row_digest_ignores_decimal_scale():
    first = row_digest((Decimal("1.20"), "a"), ["numeric", "text"])
    second = row_digest((Decimal("1.2"), "a"), ["numeric", "text"])
    assert first == second


def test_row_digest_detects_changes():
    first = row_digest((1, "a"), ["integer", "text"])
    second = row_digest((1, "b"), ["integer", "text"])
    assert first != second


def test_canonical_xml_ignores_declaration_and_padding():
    first = '<?xml version="1.0"?><producto><nombre> Demo </nombre></producto>'
    second = "<producto><nombre>Demo</nombre></producto>"
    assert canonical_value(first, "xml") == canonical_value(second, "xml")
