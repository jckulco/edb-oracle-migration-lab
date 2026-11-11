# 18. Herramientas de migración de EDB

El laboratorio se diseñó originalmente con un ETL propio para enseñar el
detalle. Ahora incorpora una **capa de herramientas EDB** para que puedas
practicar el flujo corporativo real:

```text
Evaluación          Conversión           Migración            Validación
──────────          ──────────           ─────────            ──────────
Portal / MTK   →    Portal + Copilot  →  MTK / EDB*Loader  →  LiveCompare
                                     →  ETL propio        →  validate.py
```

## Qué herramienta usar para qué

| Necesidad | Herramienta | Integración en el lab |
|---|---|---|
| Analizar DDL Oracle y ver incompatibilidades | **Migration Portal** | `make portal-export` + carga web |
| Corregir objetos difíciles con asistencia | **AI Copilot** | Prompts en `migration/edb-tools/copilot/` |
| Convertir esquema y datos con CLI | **Migration Toolkit (MTK)** | `make mtk-schema`, `make mtk-data` |
| Cargar archivos planos masivos | **EDB\*Loader** | `make edbldr-demo` |
| Comparar filas Oracle vs EPAS | **LiveCompare** | `make livecompare` |
| Reducir downtime con CDC | **Replication Server** | Guía y checklist (no automatizado) |
| Reducir reescritura de PL/SQL | **Compatibilidad EPAS** | `sql/edb/`, `docs/08-plsql-a-epas.md` |
| Validación didáctica y checksums | **ETL propio** | `make validate` |

## 1. Migration Portal

Servicio web que:

- Analiza el DDL Oracle.
- Evalúa la compatibilidad con EPAS.
- Aplica correcciones automáticas.
- Genera DDL compatible.
- Ofrece AI Copilot para errores concretos.

En el laboratorio:

```bash
make portal-export
```

Genera `migration/reports/portal/ventas_ddl.sql` y un ZIP. Luego se sube a
<https://migration.enterprisedb.com/>. El DDL descargado se contrasta con
`sql/edb/` antes de aplicarlo.

Detalle: [20-migration-portal.md](20-migration-portal.md).

## 2. Migration Toolkit (MTK)

Herramienta CLI (Java) que migra esquema y datos. Se instala aparte:

- Linux: `/usr/edb/migrationtoolkit/bin/runMTK.sh`
- Configuración: `/usr/edb/migrationtoolkit/etc/toolkit.properties`

En el laboratorio:

```bash
make tools-check
make mtk-schema     # DDL offline
make mtk-data       # datos offline
make mtk-full       # ambos
```

Los modos offline no tocan EPAS: generan artefactos en
`migration/reports/mtk/`. El modo online escribe en un esquema separado
`ventas_mtk`, nunca en `ventas`.

Detalle: [19-mtk.md](19-mtk.md).

## 3. EDB\*Loader

Cargador masivo compatible con SQL\*Loader. El laboratorio incluye una demo
con `regiones.ctl` y `regiones.dat`:

```bash
make edbldr-demo
```

Crea `ventas.regiones_ldr`, ejecuta `edbldr` dentro del contenedor y verifica
4 filas.

Detalle: [../migration/edb-tools/edbldr/README.md](../migration/edb-tools/edbldr/README.md).

## 4. LiveCompare

Compara Oracle contra EPAS fila a fila. Soporta Oracle como conexión y
PostgreSQL/EPAS como destino. Requiere:

- Binario `livecompare`.
- Base de salida en EPAS (el wrapper crea `livecompare`).
- Grants Oracle: `CONNECT`, `SELECT ANY TABLE`, `SELECT_CATALOG_ROLE`.

```bash
./scripts/12_livecompare.sh --grant
# o, si ya tienes grants:
make livecompare
```

Detalle: [21-livecompare.md](21-livecompare.md).

## 5. Replication Server (CDC)

Permite mantener Oracle y EPAS sincronizados con captura de cambios para
reducir el downtime. Es un producto separado; el laboratorio documenta la
arquitectura, los requisitos y el checklist, pero no lo instala.

Detalle: [22-replication-server.md](22-replication-server.md).

## 6. Compatibilidad EPAS

La compatibilidad Oracle de EPAS ya está demostrada en:

- Paquetes `pkg_util`, `pkg_auditoria`, `pkg_ventas`, `pkg_mantenimiento`.
- `%TYPE`, cursores, excepciones, `PRAGMA AUTONOMOUS_TRANSACTION`.
- `NVL`, `DUAL`, `CONNECT BY`, `ROWNUM`, `MERGE`.
- Triggers con `:NEW`/`:OLD`.
- `edb_redwood_date` y `edb_redwood_strings`.

No se afirma un “95 % sin reescribir” como garantía universal: el porcentaje
depende del código, las extensiones y las reglas de negocio. El laboratorio
mide lo que realmente se conserva con pruebas.

## 7. Flujo recomendado

```text
1. make oracle-load
2. make portal-export          # evaluación y conversión en Portal
3. make assess                 # assessment local complementario
4. make mtk-schema             # DDL alternativo con MTK (opcional)
5. make edb-schema
6. make migrate                # ETL propio, control fino
   o make edbldr-demo          # carga masiva puntual
   o make mtk-data             # datos offline con MTK
7. make post-load
8. make validate               # checksums + pruebas funcionales
9. make livecompare            # comparación con herramienta EDB
10. make benchmark
```

## 8. Licencias y límites

- Migration Portal: servicio de EDB, requiere cuenta.
- MTK: producto comercial, instalación y licencia aparte.
- LiveCompare: producto comercial, binario e instalación aparte.
- Replication Server: producto comercial, instalación y configuración aparte.
- EDB\*Loader: incluido con EPAS.
- AI Copilot: disponible según la edición de Migration Portal/EDB Postgres AI.

Ninguna herramienta se descarga ni se redistribuye desde este repositorio.
Las instrucciones asumen que ya tienes acceso legítimo.

## 9. Diagnóstico

```bash
make tools-check
```

Muestra qué hay instalado en el host y dentro de EPAS. Si falta algo, el
laboratorio sigue funcionando con el ETL propio y `validate.py`; las metas
`mtk-*` y `livecompare` fallan con un mensaje claro.
