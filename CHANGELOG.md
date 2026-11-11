# Changelog

Todas las modificaciones relevantes de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/)
y el proyecto adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [1.1.0] - 2026-11-10

### Añadido

- Capa de integración con herramientas EDB en `migration/edb-tools/`.
- Exportación de DDL con `DBMS_METADATA` para EDB Migration Portal.
- Prompts y flujo de revisión para Migration Portal AI Copilot.
- Wrapper de EDB Migration Toolkit (MTK) para modos offline y online aislado.
- Configuración y wrapper de EDB LiveCompare para comparar Oracle vs EPAS.
- Demostración de EDB*Loader con archivo de control y datos.
- Guía de EDB Replication Server y CDC.
- Comandos `make portal-export`, `mtk-*`, `livecompare*`, `edbldr-demo` y
  `tools-check`.
- Documentos 18 a 22.

## [1.0.0] - 2026-11-10

### Añadido

- Laboratorio completo Oracle Database Free 23ai -> EDB Postgres Advanced
  Server 16 con Docker Compose.
- Esquema `VENTAS` con 12 tablas, tipos objeto, colección anidada, LOBs,
  XMLTYPE, JSON, RAW, intervalos, identidades, columnas virtuales, índices
  B-tree, bitmap, funcionales, particionamiento opcional, vistas, vista
  materializada, paquetes PL/SQL, procedimientos, funciones y triggers.
- Esquema EPAS migrado con decisiones de conversión documentadas.
- ETL en Python (python-oracledb thin + psycopg 3 + COPY) para 12 tablas.
- Assessment automático del esquema Oracle y reporte de riesgos.
- Validación de conteos, checksums, nulos y pruebas funcionales.
- Benchmark indicativo Oracle vs EPAS.
- Documentación en español: 18 documentos, runbook, troubleshooting y
  checklist de post-migración.
- CI de GitHub Actions con lint, compilación Python y pruebas unitarias.
