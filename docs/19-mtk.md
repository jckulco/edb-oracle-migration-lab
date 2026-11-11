# 19. Migration Toolkit (MTK)

## Qué es

EDB Migration Toolkit es una herramienta CLI en Java que migra esquemas y
datos Oracle a PostgreSQL/EPAS. En el laboratorio se usa como **vía
alternativa** al DDL escrito a mano y al ETL propio.

- Documentación: <https://www.enterprisedb.com/docs/migration_toolkit/latest/>
- Ejecutable: `/usr/edb/migrationtoolkit/bin/runMTK.sh`
- Propiedades: `/usr/edb/migrationtoolkit/etc/toolkit.properties`

## Instalación y configuración

MTK es comercial. Instálalo según la guía de EDB y verifica:

```bash
java -version
/usr/edb/migrationtoolkit/bin/runMTK.sh -version
```

Configura `toolkit.properties`. La plantilla del laboratorio está en
`migration/edb-tools/mtk/toolkit.properties.example`:

```ini
SRC_DB_URL=jdbc:oracle:thin:@//localhost:1521/FREEPDB1
SRC_DB_USER=ventas
SRC_DB_PASSWORD=VentasLab_2026

TARGET_DB_URL=jdbc:edb://localhost:5444/ventas
TARGET_DB_USER=ventas
TARGET_DB_PASSWORD=VentasLab_2026
```

Cópiala a la ruta de MTK con permisos `600`:

```bash
sudo cp migration/edb-tools/mtk/toolkit.properties.example \
  /usr/edb/migrationtoolkit/etc/toolkit.properties
sudo chmod 600 /usr/edb/migrationtoolkit/etc/toolkit.properties
```

O deja que el wrapper la genere desde `.env`:

```bash
make mtk-schema   # si falta, falla con instrucciones
./scripts/10_mtk.sh offline-schema --write-properties
```

`--write-properties` hace un backup del archivo anterior.

## Modos del laboratorio

### Offline schema

```bash
make mtk-schema
```

Ejecuta, desde `migration/reports/mtk/`:

```text
runMTK.sh -offlineMigration -schemaOnly \
  -allTables -indexes -constraints -triggers \
  -allViews -allSequences -allProcs -allFuncs -allPackages -objectTypes \
  VENTAS
```

Genera archivos SQL con el DDL. **No escribe en EPAS**. Es útil para comparar
la conversión de MTK con `sql/edb/`.

### Offline data

```bash
make mtk-data
```

Genera un archivo SQL de datos con `COPY`:

```text
runMTK.sh -offlineMigration -dataOnly -singleDataFile -safeMode VENTAS
```

Puedes revisar el archivo y aplicarlo manualmente. No se aplica solo.

### Offline full

```bash
make mtk-full
```

Genera esquema y datos; revisa los artefactos antes de cargarlos.

### Online a un esquema aislado

```bash
export MTK_ALLOW_ONLINE=1
./scripts/10_mtk.sh online-schema
./scripts/10_mtk.sh online-data
```

El modo online está deshabilitado por defecto para evitar borrar
`ventas_mtk` por accidente.

Usa `-targetSchema ventas_mtk -dropSchema true`, así que **no toca** el
esquema `ventas` del laboratorio. Es una vía para comparar resultados.

Advertencia: `-dropSchema true` elimina `ventas_mtk` si existe. No lo ejecutes
sobre un esquema con datos que necesites.

## Artefactos

```text
migration/reports/mtk/
├── mtk_schema.log
├── mtk_data.log
├── mtk_full.log
├── logs/
└── (archivos .sql generados por MTK)
```

Los archivos contienen credenciales solo si MTK las incluye; revisa antes de
compartirlos. El directorio está bajo `migration/reports/`, ignorado por Git.

## Qué revisar en el DDL de MTK

1. `NUMBER` → `numeric`/`bigint`/`double`.
2. `DATE` → `timestamp` o `date`.
3. `CLOB`/`BLOB` → `text`/`bytea`/Large Objects.
4. Objetos y nested tables.
5. Nombres en mayúsculas/minúsculas (`-useOraCase`).
6. Paquetes y `DBMS_*`.
7. MVs y `REFRESH FAST`.
8. Triggers compuestos o `INSTEAD OF`.
9. Secuencias e identidades.
10. Índices bitmap/IOT.

## Comparar con el laboratorio

```bash
make mtk-schema
diff -u sql/edb/01_tables.sql migration/reports/mtk/mtk_ventas_ddl.sql | less
```

El nombre exacto del archivo generado depende de la versión de MTK. Busca:

```bash
find migration/reports/mtk -maxdepth 2 -name '*.sql'
```

No apliques el DDL de MTK sobre `ventas` sin revisar y sin un backup; el
laboratorio ya tiene su DDL validado.

## Limitaciones

- MTK no conoce las reglas de negocio ni la estrategia de secuencias/triggers.
- El modo online puede cambiar nombres y tipos.
- La carga de LOBs/JSON/XML requiere revisión.
- La salida no es idempotente.
- No sustituye `make validate` ni LiveCompare.
- Requiere Java y licencia.

## Referencias

- [Invocación de MTK](https://www.enterprisedb.com/docs/migration_toolkit/latest/07_invoking_mtk/)
- [Opciones de comando](https://www.enterprisedb.com/docs/migration_toolkit/latest/07_invoking_mtk/08_mtk_command_options/)
- [toolkit.properties](https://www.enterprisedb.com/docs/migration_toolkit/latest/06_building_toolkit.properties_file/)
