#!/usr/bin/env python3
"""Assessment automático del esquema Oracle antes de migrar.

Inspecciona el diccionario de datos (vistas USER_*) y genera:
  * migration/reports/assessment.md   (legible para el equipo)
  * migration/reports/assessment.json (para automatización)

No modifica la base de datos. Se ejecuta como el usuario de aplicación.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from . import oracle_source
from .config import ConfigError, Settings, load_manifest

HIGH = "ALTO"
MEDIUM = "MEDIO"
LOW = "BAJO"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, help="Directorio de reportes")
    return parser.parse_args()


def query(conn, sql: str, params: dict | None = None) -> list[tuple[Any, ...]]:
    with conn.cursor() as cur:
        cur.execute(sql, params or {})
        return cur.fetchall()


def safe_query(conn, sql: str) -> list[tuple[Any, ...]]:
    try:
        return query(conn, sql)
    except Exception:  # noqa: BLE001 - algunas vistas no existen según la edición
        return []


def collect(conn) -> dict[str, Any]:
    manifest = load_manifest()
    object_counts = query(
        conn,
        """
        SELECT object_type, COUNT(*)
          FROM user_objects
         GROUP BY object_type
         ORDER BY 2 DESC, 1
        """,
    )
    table_counts: list[dict[str, Any]] = []
    total_rows = 0
    for spec in manifest.tables:
        rows = int(oracle_source.scalar(conn, f'SELECT COUNT(*) FROM "{spec.name.upper()}"') or 0)
        total_rows += rows
        table_counts.append({"table": spec.name, "rows": rows})

    column_types = query(
        conn,
        """
        SELECT data_type, COUNT(*) AS columnas, COUNT(DISTINCT table_name) AS tablas
          FROM user_tab_columns
         GROUP BY data_type
         ORDER BY columnas DESC, data_type
        """,
    )
    special_columns = query(
        conn,
        """
        SELECT table_name, column_name, data_type, data_length, char_length
          FROM user_tab_columns
         WHERE data_type IN ('CLOB', 'NCLOB', 'BLOB', 'RAW', 'LONG', 'XMLTYPE',
                             'BINARY_FLOAT', 'BINARY_DOUBLE', 'JSON')
            OR data_type LIKE 'TIMESTAMP%'
            OR data_type LIKE 'INTERVAL%'
            OR data_type IN ('ROWID', 'UROWID', 'BFILE')
         ORDER BY table_name, column_id
        """,
    )
    indexes = query(
        conn,
        """
        SELECT table_name, index_name, index_type, uniqueness, status
          FROM user_indexes
         ORDER BY table_name, index_name
        """,
    )
    constraints = query(
        conn,
        """
        SELECT constraint_type, COUNT(*)
          FROM user_constraints
         GROUP BY constraint_type
         ORDER BY constraint_type
        """,
    )
    mviews = safe_query(
        conn,
        """
        SELECT mview_name, refresh_mode, refresh_method, staleness, compile_state
          FROM user_mviews
         ORDER BY mview_name
        """,
    )
    partitions = safe_query(
        conn,
        """
        SELECT table_name, partitioning_type, partition_count, status
          FROM user_part_tables
         ORDER BY table_name
        """,
    )
    user_types = safe_query(
        conn,
        """
        SELECT type_name, typecode, attributes, methods
          FROM user_types
         WHERE type_name NOT LIKE 'SYS\\_%' ESCAPE '\\'
         ORDER BY type_name
        """,
    )
    nested_tables = safe_query(
        conn,
        """
        SELECT table_name, table_type_name, parent_table_name
          FROM user_nested_tables
         ORDER BY parent_table_name, table_name
        """,
    )
    synonyms = safe_query(
        conn, "SELECT synonym_name, table_owner, table_name FROM user_synonyms"
    )
    db_links = safe_query(
        conn, "SELECT db_link, username, host FROM user_db_links"
    )
    jobs = safe_query(
        conn,
        "SELECT job, what, broken FROM user_jobs ORDER BY job",
    )
    triggers = safe_query(
        conn,
        """
        SELECT trigger_name, table_name, trigger_type, triggering_event, status
          FROM user_triggers
         ORDER BY table_name, trigger_name
        """,
    )
    segments = safe_query(
        conn,
        """
        SELECT segment_type, COUNT(*) AS segmentos, SUM(bytes) AS bytes
          FROM user_segments
         GROUP BY segment_type
         ORDER BY bytes DESC
        """,
    )
    plsql = query(
        conn,
        """
        SELECT object_type, COUNT(*)
          FROM user_objects
         WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'PROCEDURE',
                               'FUNCTION', 'TRIGGER', 'TYPE', 'TYPE BODY')
         GROUP BY object_type
         ORDER BY object_type
        """,
    )

    return {
        "generated_at": datetime.now(UTC).isoformat(),
        "oracle_version": oracle_source.version(conn),
        "schema": manifest.oracle_schema,
        "manifest_tables": manifest.table_names,
        "total_rows": total_rows,
        "table_counts": table_counts,
        "object_counts": [{"type": r[0], "count": int(r[1])} for r in object_counts],
        "column_types": [
            {"data_type": r[0], "columns": int(r[1]), "tables": int(r[2])}
            for r in column_types
        ],
        "special_columns": [
            {
                "table": r[0],
                "column": r[1],
                "data_type": r[2],
                "data_length": r[3],
                "char_length": r[4],
            }
            for r in special_columns
        ],
        "indexes": [
            {
                "table": r[0],
                "index": r[1],
                "type": r[2],
                "unique": r[3],
                "status": r[4],
            }
            for r in indexes
        ],
        "constraints": [{"type": r[0], "count": int(r[1])} for r in constraints],
        "mviews": [
            {
                "name": r[0],
                "refresh_mode": r[1],
                "refresh_method": r[2],
                "staleness": r[3],
                "state": r[4],
            }
            for r in mviews
        ],
        "partitions": [
            {
                "table": r[0],
                "type": r[1],
                "count": int(r[2]),
                "status": r[3],
            }
            for r in partitions
        ],
        "user_types": [
            {"name": r[0], "typecode": r[1], "attributes": r[2], "methods": r[3]}
            for r in user_types
        ],
        "nested_tables": [
            {"table": r[0], "type": r[1], "parent": r[2]} for r in nested_tables
        ],
        "synonyms": [
            {"name": r[0], "owner": r[1], "table": r[2]} for r in synonyms
        ],
        "db_links": [{"link": r[0], "user": r[1], "host": r[2]} for r in db_links],
        "jobs": [{"job": r[0], "what": r[1], "broken": r[2]} for r in jobs],
        "triggers": [
            {
                "name": r[0],
                "table": r[1],
                "type": r[2],
                "event": r[3],
                "status": r[4],
            }
            for r in triggers
        ],
        "segments": [
            {"type": r[0], "count": int(r[1]), "bytes": int(r[2] or 0)}
            for r in segments
        ],
        "plsql": [{"type": r[0], "count": int(r[1])} for r in plsql],
    }


def build_findings(data: dict[str, Any]) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []

    def add(level: str, finding: str, impact: str, action: str) -> None:
        findings.append(
            {"nivel": level, "hallazgo": finding, "impacto": impact, "accion": action}
        )

    if data["user_types"]:
        add(
            HIGH,
            f"{len(data['user_types'])} tipos definidos por el usuario",
            "Los objetos, VARRAY y colecciones no se copian 1:1.",
            "Rediseñar a columnas planas, arreglos, JSONB o tablas hijas.",
        )
    if data["nested_tables"]:
        add(
            HIGH,
            f"{len(data['nested_tables'])} nested table(s)",
            "No existe una nested table equivalente en EPAS.",
            "Convertir a text[], JSONB o tabla hija con FK.",
        )
    if data["mviews"]:
        add(
            HIGH,
            f"{len(data['mviews'])} vista(s) materializada(s)",
            "EPAS no soporta REFRESH FAST ON COMMIT.",
            "Usar REFRESH MATERIALIZED VIEW (completo) y programar el refresco.",
        )
    if data["partitions"]:
        add(
            MEDIUM,
            f"{len(data['partitions'])} tabla(s) particionada(s)",
            "El particionamiento no se migra automáticamente.",
            "Rediseñar con PARTITION BY RANGE/LIST/HASH y probar la poda.",
        )
    if data["synonyms"]:
        add(
            MEDIUM,
            f"{len(data['synonyms'])} sinónimo(s)",
            "Los sinónimos no son parte del estándar PostgreSQL.",
            "Reemplazar por search_path, vistas o nombres calificados.",
        )
    if data["db_links"]:
        add(
            HIGH,
            f"{len(data['db_links'])} database link(s)",
            "No hay DB links Oracle nativos en EPAS.",
            "Usar dblink/postgres_fdw/edb_dblink_oci o reescribir la integración.",
        )
    if data["jobs"]:
        add(
            MEDIUM,
            f"{len(data['jobs'])} job(s) de Oracle",
            "DBMS_JOB/DBMS_SCHEDULER no están disponibles tal cual.",
            "Migrar a pg_cron, un scheduler externo o el jobs de EPAS.",
        )

    bitmap = [i for i in data["indexes"] if "BITMAP" in i["type"].upper()]
    if bitmap:
        add(
            MEDIUM,
            f"{len(bitmap)} índice(s) bitmap",
            "EPAS no implementa índices bitmap.",
            "Usar btree, BRIN, índices parciales o particionamiento.",
        )
    function_based = [i for i in data["indexes"] if "FUNCTION-BASED" in i["type"].upper()]
    if function_based:
        add(
            LOW,
            f"{len(function_based)} índice(s) funcional(es)",
            "Se recrean como índices de expresión; validar inmutabilidad.",
            "Crear el índice sobre la misma expresión y ANALYZE.",
        )
    if any("IOT" in i["type"].upper() for i in data["indexes"]):
        add(
            MEDIUM,
            "Índice organizado por tabla (IOT)",
            "No hay IOT en EPAS.",
            "Usar PRIMARY KEY + CLUSTER o una tabla con el orden físico deseado.",
        )

    lob_columns = [
        c
        for c in data["special_columns"]
        if c["data_type"] in {"CLOB", "NCLOB", "BLOB", "LONG"}
    ]
    if lob_columns:
        add(
            LOW,
            f"{len(lob_columns)} columna(s) LOB/LONG",
            "CLOB/BLOB se migran a text/bytea; LONG es obsoleto.",
            "Validar tamaño, codificación y uso de DBMS_LOB en el código.",
        )
    if any(c["data_type"] == "XMLTYPE" for c in data["special_columns"]):
        add(
            MEDIUM,
            "Columnas XMLTYPE",
            "Se migran a xml; las funciones y validaciones cambian.",
            "Probar XPath/XQuery y el tamaño de los documentos.",
        )
    if any(c["data_type"] == "JSON" for c in data["special_columns"]):
        add(
            LOW,
            "Columnas JSON nativas",
            "Se migran a jsonb; cambian operadores y rutas.",
            "Reescribir consultas JSON y validar índices GIN.",
        )
    if any(c["data_type"] in {"RAW"} for c in data["special_columns"]):
        add(
            LOW,
            "Columnas RAW",
            "Se migran a bytea.",
            "Revisar funciones de hash/GUID y comparaciones binarias.",
        )
    if any("WITH TIME ZONE" in c["data_type"] for c in data["special_columns"]):
        add(
            LOW,
            "Columnas con zona horaria",
            "TIMESTAMP WITH LOCAL TIME ZONE depende de la zona de sesión.",
            "Estandarizar la sesión a UTC y probar los cambios de horario.",
        )
    if any("INTERVAL" in c["data_type"] for c in data["special_columns"]):
        add(
            LOW,
            "Columnas INTERVAL",
            "El tipo interval de PostgreSQL no conserva meses/años de la misma forma.",
            "Validar aritmética y formato; considerar columnas separadas.",
        )

    plsql_total = sum(p["count"] for p in data["plsql"])
    if plsql_total:
        add(
            MEDIUM,
            f"{plsql_total} unidad(es) PL/SQL",
            "EPAS soporta paquetes y PL/SQL, pero no todas las construcciones.",
            "Compilar, probar y revisar BULK COLLECT, FORALL, compound triggers y DBMS_*.",
        )
    if data["triggers"]:
        add(
            LOW,
            f"{len(data['triggers'])} trigger(s)",
            "La sintaxis Oracle es compatible en EPAS, con excepciones.",
            "Probar ORDER, FOLLOWS, INSTEAD OF, statement-level y autonomous.",
        )

    if not findings:
        add(
            LOW,
            "Sin hallazgos de alto riesgo",
            "El esquema usa construcciones mayormente portables.",
            "Aun así, ejecutar la validación de datos y las pruebas funcionales.",
        )
    return findings


def compatibility_score(findings: list[dict[str, str]]) -> int:
    penalty = {HIGH: 8, MEDIUM: 3, LOW: 1}
    score = 100 - sum(penalty.get(f["nivel"], 1) for f in findings)
    return max(0, min(100, score))


def build_markdown(data: dict[str, Any], findings: list[dict[str, str]]) -> str:
    score = compatibility_score(findings)
    lines: list[str] = []
    lines.append("# Assessment de migración Oracle -> EPAS")
    lines.append("")
    lines.append(f"- **Generado:** {data['generated_at']}")
    lines.append(f"- **Esquema:** `{data['schema']}`")
    lines.append(f"- **Versión Oracle:** {data['oracle_version']}")
    lines.append(f"- **Tablas del manifiesto:** {len(data['manifest_tables'])}")
    lines.append(f"- **Filas totales:** {data['total_rows']:,}")
    lines.append(f"- **Índice de compatibilidad estimado:** **{score}/100**")
    lines.append("")
    lines.append("> El índice es una heurística educativa, no una garantía. "
                 "La validación real se hace con datos y pruebas funcionales.")
    lines.append("")
    lines.append("## Hallazgos y acciones")
    lines.append("")
    lines.append("| Nivel | Hallazgo | Impacto | Acción recomendada |")
    lines.append("|---|---|---|---|")
    for f in findings:
        lines.append(
            f"| {f['nivel']} | {f['hallazgo']} | {f['impacto']} | {f['accion']} |"
        )
    lines.append("")

    lines.append("## Filas por tabla")
    lines.append("")
    lines.append("| Tabla | Filas |")
    lines.append("|---|---:|")
    for t in data["table_counts"]:
        lines.append(f"| `{t['table']}` | {t['rows']:,} |")
    lines.append("")

    lines.append("## Inventario de objetos")
    lines.append("")
    lines.append("| Tipo | Cantidad |")
    lines.append("|---|---:|")
    for o in data["object_counts"]:
        lines.append(f"| {o['type']} | {o['count']} |")
    lines.append("")

    lines.append("## Tipos de dato")
    lines.append("")
    lines.append("| Tipo Oracle | Columnas | Tablas |")
    lines.append("|---|---:|---:|")
    for c in data["column_types"]:
        lines.append(f"| {c['data_type']} | {c['columns']} | {c['tables']} |")
    lines.append("")

    if data["indexes"]:
        lines.append("## Índices")
        lines.append("")
        lines.append("| Tabla | Índice | Tipo | Único | Estado |")
        lines.append("|---|---|---|---|---|")
        for i in data["indexes"]:
            lines.append(
                f"| `{i['table']}` | `{i['index']}` | {i['type']} | "
                f"{i['unique']} | {i['status']} |"
            )
        lines.append("")

    if data["special_columns"]:
        lines.append("## Columnas especiales")
        lines.append("")
        lines.append("| Tabla | Columna | Tipo | Longitud |")
        lines.append("|---|---|---|---:|")
        for c in data["special_columns"]:
            length = c["char_length"] or c["data_length"]
            lines.append(
                f"| `{c['table']}` | `{c['column']}` | {c['data_type']} | {length} |"
            )
        lines.append("")

    if data["mviews"]:
        lines.append("## Vistas materializadas")
        lines.append("")
        lines.append("| MV | Refresh | Método | Staleness |")
        lines.append("|---|---|---|---|")
        for m in data["mviews"]:
            lines.append(
                f"| `{m['name']}` | {m['refresh_mode']} | {m['refresh_method']} | "
                f"{m['staleness']} |"
            )
        lines.append("")

    lines.append("## Siguientes pasos")
    lines.append("")
    lines.append("1. Revisar los hallazgos ALTO y MEDIO con el equipo de negocio.")
    lines.append("2. Ajustar `migration/config/migration.yaml` y el DDL destino.")
    lines.append("3. Ejecutar `make migrate` y `make validate`.")
    lines.append("4. Documentar las decisiones en `docs/06-migracion-esquema.md`.")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    try:
        settings = Settings.from_env()
    except (ConfigError, ValueError) as exc:
        print(f"ERROR de configuración: {exc}", file=sys.stderr)
        return 2

    out_dir = args.out_dir or settings.report_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        conn = oracle_source.connect(settings.oracle)
        data = collect(conn)
        conn.close()
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR durante el assessment: {exc}", file=sys.stderr)
        return 3

    findings = build_findings(data)
    data["findings"] = findings
    data["compatibility_score"] = compatibility_score(findings)

    json_path = out_dir / "assessment.json"
    md_path = out_dir / "assessment.md"
    json_path.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    md_path.write_text(build_markdown(data, findings) + "\n", encoding="utf-8")

    print(f"Assessment generado: {md_path}")
    print(f"JSON:                {json_path}")
    print(f"Compatibilidad:      {data['compatibility_score']}/100")
    print(f"Hallazgos:           {len(findings)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
