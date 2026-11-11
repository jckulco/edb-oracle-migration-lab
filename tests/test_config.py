import pytest

from migration.etl.config import (
    ConfigError,
    TableSpec,
    load_benchmark_specs,
    load_manifest,
    load_test_specs,
)


def test_manifest_has_expected_tables():
    manifest = load_manifest()
    assert len(manifest.tables) == 12
    assert manifest.table_names[0] == "regiones"
    assert manifest.table_names[-1] == "precios_historial"
    assert [t.order for t in manifest.tables] == sorted(t.order for t in manifest.tables)


def test_manifest_table_columns_match_select_shape():
    manifest = load_manifest()
    for table in manifest.tables:
        assert table.columns, table.name
        assert table.select.strip(), table.name
        assert table.pk, table.name
    clientes = manifest.table("clientes")
    assert "dir_calle" in clientes.columns
    assert "telefonos" in clientes.columns


def test_manifest_sequences_and_identities():
    manifest = load_manifest()
    names = {s.name for s in manifest.sequences}
    assert {"seq_clientes", "seq_pedidos", "seq_pagos"} <= names
    identity_tables = {i.table for i in manifest.identity_columns}
    assert {"productos", "pedido_detalle", "auditoria_cambios"} <= identity_tables


def test_table_spec_rejects_semicolon():
    spec = TableSpec(
        name="t",
        columns=("id",),
        select="SELECT id FROM t;",
        pk=("id",),
        order=1,
    )
    with pytest.raises(ConfigError):
        spec.validate()


def test_functional_tests_have_both_queries():
    tests = load_test_specs()
    assert len(tests) >= 10
    for test in tests:
        assert test["oracle"].strip()
        assert test["edb"].strip()


def test_benchmark_queries_have_both_queries():
    queries = load_benchmark_specs()
    assert len(queries) >= 3
    for query in queries:
        assert query["oracle"].strip()
        assert query["edb"].strip()
