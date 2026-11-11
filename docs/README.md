# Documentación del laboratorio

Este directorio concentra la documentación en español. El recorrido está
pensado para leerse en orden, pero cada documento es autocontenido.

## Ruta de aprendizaje

| # | Documento | Qué resuelve |
|---|---|---|
| 00 | [Introducción](00-introduccion.md) | Alcance, objetivos y historia del laboratorio |
| 01 | [Arquitectura](01-arquitectura.md) | Componentes, puertos, flujo y decisiones |
| 02 | [Requisitos](02-requisitos.md) | Hardware, software, licencias y primer arranque |
| 03 | [Docker Oracle y EDB](03-docker-oracle-edb.md) | Habilitar ambas bases, credenciales, volúmenes y conexión |
| 04 | [Modelo de datos](04-modelo-datos.md) | Tablas, relaciones y objetos del esquema VENTAS |
| 05 | [Mapeo de tipos](05-mapeo-tipos-datos.md) | Oracle → EPAS, con matices y ejemplos |
| 06 | [Migración de esquema](06-migracion-esquema.md) | DDL, objetos, secuencias, restricciones y decisiones |
| 07 | [Migración de datos](07-migracion-datos.md) | ETL, COPY, LOBs, JSON, XML, arrays y orden de carga |
| 08 | [PL/SQL a EPAS](08-plsql-a-epas.md) | Paquetes, procedimientos, triggers y compatibilidad |
| 09 | [Índices y rendimiento](09-indices-rendimiento.md) | Índices, estadísticas, planes y benchmark |
| 10 | [Vistas y materializadas](10-vistas-mv.md) | Vistas, MV, refresco y brechas de Oracle |
| 11 | [Triggers y secuencias](11-triggers-secuencias.md) | Auditoría, autonomía, identidades y resync |
| 12 | [Validación](12-validacion.md) | Conteos, checksums, nulos y pruebas funcionales |
| 13 | [Runbook](13-runbook.md) | Comandos de principio a fin |
| 14 | [Troubleshooting](14-troubleshooting.md) | Errores frecuentes y cómo diagnosticarlos |
| 15 | [Post-migración](15-post-migracion.md) | Cutover, performance, seguridad y operación |
| 16 | [Ora2Pg](16-ora2pg.md) | La herramienta complementaria |
| 17 | [Referencias](17-referencias.md) | Enlaces oficiales y lecturas |
| 18 | [Herramientas EDB](18-herramientas-edb.md) | Portal, MTK, LiveCompare, EDB*Loader, Copilot y CDC |
| 19 | [Migration Toolkit](19-mtk.md) | MTK offline/online, configuración y artefactos |
| 20 | [Migration Portal](20-migration-portal.md) | Exportar DDL, evaluar y usar AI Copilot |
| 21 | [LiveCompare](21-livecompare.md) | Comparación fila a fila Oracle vs EPAS |
| 22 | [Replication Server](22-replication-server.md) | CDC, cutover y fallback |

## Convenciones

- **Oracle**: identificadores en mayúsculas, SQL*Plus, esquema `VENTAS`.
- **EPAS**: identificadores en minúsculas, `edb-psql`, esquema `ventas`.
- Los bloques `bash` se ejecutan desde la raíz del repositorio.
- Los reportes se generan en `migration/reports/` y no se versionan.
- Los ejemplos usan las credenciales de `.env.example`; cámbialas.

## Atajos

```bash
make help       # objetivos disponibles
make all        # flujo completo sin validación
make validate   # comparación de datos y pruebas funcionales
```

## Advertencia

EDB Postgres Advanced Server es software comercial. La imagen de contenedor
requiere acceso al registro de EDB y una licencia o periodo de evaluación
válido. Oracle Database Free es gratuita dentro de sus límites de edición.
Revisa [03-docker-oracle-edb.md](03-docker-oracle-edb.md) antes de empezar.
