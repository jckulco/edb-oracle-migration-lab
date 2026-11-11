# EDB Migration Toolkit (MTK)

MTK es la herramienta CLI de EDB para migrar esquemas y datos. Es comercial y
se instala aparte del laboratorio.

- Documentación: <https://www.enterprisedb.com/docs/migration_toolkit/latest/>
- Ejecutable Linux: `/usr/edb/migrationtoolkit/bin/runMTK.sh`
- Configuración: `/usr/edb/migrationtoolkit/etc/toolkit.properties`

## Requisitos

- Java (el instalador de MTK puede incluir su propio JRE; revisa la guía).
- Acceso al Oracle de origen.
- Acceso al EPAS destino.
- Licencia/instalación de MTK.
- `toolkit.properties` legible por el usuario que ejecuta MTK.

## Configuración

Copia la plantilla y ajusta los valores:

```bash
sudo cp migration/edb-tools/mtk/toolkit.properties.example \
  /usr/edb/migrationtoolkit/etc/toolkit.properties
sudo chmod 600 /usr/edb/migrationtoolkit/etc/toolkit.properties
```

O deja que el wrapper lo genere desde `.env` (hace backup del anterior):

```bash
./scripts/10_mtk.sh offline-schema --write-properties
```

## Modos del wrapper

```bash
# DDL offline en migration/reports/mtk/ (no toca EPAS)
./scripts/10_mtk.sh offline-schema

# Datos offline en un único archivo SQL
./scripts/10_mtk.sh offline-data

# Esquema + datos offline
./scripts/10_mtk.sh offline-full

# Migración online a un esquema separado ventas_mtk
export MTK_ALLOW_ONLINE=1
./scripts/10_mtk.sh online-schema
./scripts/10_mtk.sh online-data
```

El modo online usa `-targetSchema ventas_mtk -dropSchema true`; **no toca el
esquema `ventas`** del laboratorio. Es una vía alternativa para comparar el
resultado de MTK con el DDL escrito a mano.

## Opciones usadas

```text
-offlineMigration -schemaOnly
-allTables -indexes -constraints -triggers
-allViews -allSequences -allProcs -allFuncs -allPackages -objectTypes
-logDir ... -verbose on
```

Para datos offline:

```text
-offlineMigration -dataOnly -singleDataFile -safeMode
```

## Problemas frecuentes

| Error | Causa | Solución |
|---|---|---|
| `runMTK.sh: not found` | MTK no instalado o `MTK_HOME` incorrecto | Ajusta `MTK_BIN`/`MTK_HOME` |
| `Invalid file permissions` | `toolkit.properties` no legible | `chmod 600`, dueño correcto |
| `ORA-01017` | Credenciales Oracle | Revisa `.env` y el properties |
| `Connection refused` | Contenedor no healthy o host incorrecto | `make ps`; usa `localhost` desde el host |
| `Package Body is Invalid` | Objeto no compatible | Revisa el log y el DDL generado |
| `Table ... does not exist` | Orden o filtro de objetos | Revisa opciones y schema scope |

## Limitaciones

- El DDL generado por MTK no es idéntico al DDL didáctico del laboratorio.
- Los objetos especiales (objetos, nested tables, MVs, triggers compuestos)
  requieren revisión.
- La migración online puede crear objetos con nombres y tipos distintos.
- No sustituye la validación de datos ni las pruebas funcionales.
- No ejecutes el modo online sobre una base con datos que no puedas perder.

## Referencias

- [Toolkit properties](https://www.enterprisedb.com/docs/migration_toolkit/latest/06_building_toolkit.properties_file/)
- [Opciones de comando](https://www.enterprisedb.com/docs/migration_toolkit/latest/07_invoking_mtk/08_mtk_command_options/)
- [Invocación](https://www.enterprisedb.com/docs/migration_toolkit/latest/07_invoking_mtk/)
