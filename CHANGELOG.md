# Changelog

Todas las modificaciones relevantes de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/)
y el proyecto adhiere a [Semantic Versioning](https://semver.org/lang/es/).

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
