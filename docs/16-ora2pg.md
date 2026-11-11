# 16. Ora2Pg como herramienta complementaria

## Qué es

Ora2Pg es una herramienta open source escrita en Perl que migra esquemas
Oracle a PostgreSQL/EPAS. Puede:

- Analizar el esquema y estimar el esfuerzo.
- Generar DDL de tablas, índices, vistas, secuencias, paquetes y triggers.
- Exportar datos con `COPY`.
- Detectar objetos incompatibles.

No es un botón mágico: el DDL generado hay que revisarlo, y los objetos
especiales (objetos, nested tables, MVs con refresco rápido, `DBMS_*`) suelen
requerir trabajo manual.

## Instalación

Ora2Pg necesita Perl, `DBD::Oracle` y Oracle Instant Client. No funciona solo
con `python-oracledb` thin.

Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y ora2pg
# Alternativa:
sudo apt-get install -y libdbd-oracle-perl
sudo cpanm Ora2Pg
```

RHEL/OL:

```bash
sudo dnf install -y perl-DBD-Oracle ora2pg
```

También hay imágenes comunitarias de Docker con Instant Client. Revisa su
procedencia y fija la versión.

## Configuración del laboratorio

El archivo `migration/ora2pg/ora2pg.conf` apunta a los servicios de Compose:

```text
ORACLE_DSN  dbi:Oracle:host=oracle;service_name=FREEPDB1;port=1521
ORACLE_USER ventas
ORACLE_PWD  VentasLab_2026
SCHEMA      VENTAS

PG_DSN   dbi:Pg:dbname=ventas;host=edb;port=5444
PG_USER  ventas
PG_PWD   VentasLab_2026
PG_VERSION 16
```

Si ejecutas Ora2Pg desde el host, cambia `oracle`/`edb` por `localhost`.

## Comandos

### Assessment

```bash
ora2pg -t SHOW_REPORT -c migration/ora2pg/ora2pg.conf \
  -o migration/reports/ora2pg_report.html
```

### Inventario

```bash
ora2pg -t SHOW_TABLE  -c migration/ora2pg/ora2pg.conf
ora2pg -t SHOW_COLUMN -c migration/ora2pg/ora2pg.conf
```

### DDL

```bash
mkdir -p /tmp/ora2pg
ora2pg -t TYPE     -c migration/ora2pg/ora2pg.conf -o /tmp/ora2pg/types.sql
ora2pg -t SEQUENCE -c migration/ora2pg/ora2pg.conf -o /tmp/ora2pg/sequences.sql
ora2pg -t TABLE    -c migration/ora2pg/ora2pg.conf -o /tmp/ora2pg/tables.sql
ora2pg -t INDEX    -c migration/ora2pg/ora2pg.conf -o /tmp/ora2pg/indexes.sql
ora2pg -t VIEW     -c migration/ora2pg/ora2pg.conf -o /tmp/ora2pg/views.sql
ora2pg -t MVIEW    -c migration/ora2pg/ora2pg.conf -o /tmp/ora2pg/mviews.sql
ora2pg -t PACKAGE  -c migration/ora2pg/ora2pg.conf -o /tmp/ora2pg/packages.sql
ora2pg -t TRIGGER  -c migration/ora2pg/ora2pg.conf -o /tmp/ora2pg/triggers.sql
```

### Datos

```bash
ora2pg -t COPY -c migration/ora2pg/ora2pg.conf -o /tmp/ora2pg/data.sql
```

### Carga

```bash
psql "host=localhost port=5444 dbname=ventas user=ventas" \
  -v ON_ERROR_STOP=1 -f /tmp/ora2pg/tables.sql
```

## Qué revisar siempre

1. `NUMBER` sin precisión: ¿`numeric`, `bigint`, `double`?
2. `DATE`: ¿se perdió la hora?
3. `CLOB`/`BLOB`: ¿`text`/`bytea` o Large Objects?
4. Objetos, nested tables y VARRAY: rediseño.
5. MVs: no hay `REFRESH FAST ON COMMIT`.
6. Paquetes: compilar con `edb-psql` y revisar `DBMS_*`.
7. Triggers: `INSTEAD OF`, `COMPOUND`, `FOLLOWS`.
8. Secuencias: resync.
9. Índices bitmap/IOT/reverse.
10. Sinónimos, DB links, jobs, directorios.

## Ora2Pg vs ETL del laboratorio

| Aspecto | Ora2Pg | ETL Python |
|---|---|---|
| DDL | Muy completo | Manual y didáctico |
| Datos | `COPY`, paralelo | `COPY`, secuencial |
| LOBs | Soporte variable | Control explícito |
| JSON/XML/arrays | Requiere ajustes | Conversión explícita |
| Validación | Limitada | Checksums + funcional |
| Curva | Media/alta | Baja para el alcance |

En un proyecto real se combinan: Ora2Pg para assessment/DDL y un ETL propio o
comercial para datos y validación.

## Limitaciones

- Ora2Pg no conoce tus reglas de negocio.
- El DDL generado puede no ser idempotente.
- Los nombres y mayúsculas pueden cambiar.
- La salida de datos puede ser enorme; usa `FILE_PER_TABLE`/paralelismo.
- No reemplaza las pruebas funcionales.

## Más información

- [README de Ora2Pg en este repositorio](../migration/ora2pg/README.md)
- <https://github.com/darold/ora2pg>
- <https://ora2pg.darold.net/>

## Siguiente paso

[17-referencias.md](17-referencias.md).
