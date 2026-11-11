# Herramientas de migración EDB en el laboratorio

Este directorio conecta el laboratorio con las herramientas comerciales de
EDB para migrar Oracle. No todas se pueden automatizar igual:

| Herramienta | Tipo | Integración en el lab | Archivo |
|---|---|---|---|
| Migration Portal | SaaS/web | Exportación de DDL + carga manual + AI Copilot | `migration-portal/` |
| Migration Toolkit (MTK) | CLI Java | Wrapper para modos offline/online | `mtk/` |
| Replication Server | Producto/servicio | Diseño, requisitos y checklist de CDC | `replication-server/` |
| LiveCompare | CLI | Comparación fila a fila Oracle vs EPAS | `livecompare/` |
| EDB\*Loader | CLI de EPAS | Carga de un `.dat` con `.ctl` | `edbldr/` |
| AI Copilot | Web (Portal) | Prompts y flujo de revisión | `copilot/` |
| Compatibilidad EPAS | Motor | Ya cubierta por `sql/edb/` y las pruebas | `docs/08-plsql-a-epas.md` |

## Estado de cada integración

- **Automatizada**: EDB\*Loader, LiveCompare, MTK (si está instalado), export
  de DDL para Migration Portal.
- **Asistida**: Migration Portal y AI Copilot (requieren navegador/cuenta).
- **Documentada, no automatizada**: Replication Server (requiere una
  instalación y configuración de CDC específicas).

Ninguna herramienta comercial se descarga ni se redistribuye desde este
repositorio. Debes instalarla y licenciarla por separado.

## Comandos rápidos

```bash
make tools-check        # qué hay instalado
make portal-export      # DDL para Migration Portal
make mtk-schema         # DDL con MTK offline (si está instalado)
make mtk-data           # datos con MTK offline (si está instalado)
make livecompare-dry-run
make livecompare        # requiere `livecompare` y grants Oracle
make edbldr-demo       # EDB*Loader dentro del contenedor
```

## Variables

```dotenv
EDB_LIVECOMPARE_DB=livecompare
MTK_HOME=/usr/edb/migrationtoolkit
LIVECOMPARE_BIN=livecompare
```

`MTK_BIN`, `MTK_PROPERTIES` y `MTK_OUT_DIR` también se pueden sobrescribir.

## Orden recomendado

```text
1. make oracle-load
2. make portal-export        -> evaluar/convertir en Migration Portal
3. make assess               -> assessment local complementario
4. make mtk-schema           -> DDL alternativo con MTK (opcional)
5. make edb-schema
6. make migrate              -> ETL propio (recomendado para el lab)
   o make mtk-data / carga con EDB*Loader para casos concretos
7. make post-load
8. make validate             -> checksums propios
9. make livecompare          -> comparación con herramienta EDB
10. make benchmark
```

## Advertencia

Las herramientas de EDB son comerciales. Revisa la licencia de cada producto
y no las uses con datos reales sin una autorización y un entorno controlado.
