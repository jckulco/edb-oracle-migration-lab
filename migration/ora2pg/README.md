# Ora2Pg como herramienta complementaria

Ora2Pg es un migrador open source (Perl) muy usado para pasar Oracle a
PostgreSQL/EPAS. En este laboratorio **no es la ruta principal**: el ETL en
Python ofrece control explícito sobre LOBs, JSON, XML, arreglos y validación.
Aun así, Ora2Pg es valioso para:

- Assessment rápido del esquema y de los objetos.
- Generar DDL inicial que luego se revisa a mano.
- Migrar volúmenes grandes con `COPY` y paralelismo.
- Detectar objetos incompatibles.

## Requisitos

Ora2Pg necesita Perl, `DBD::Oracle` y Oracle Instant Client (o un cliente
Oracle completo). No funciona solo con `python-oracledb` thin.

## Instalación típica en Debian/Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y ora2pg
# o, si el paquete no está disponible:
sudo apt-get install -y libdbd-oracle-perl
sudo cpanm Ora2Pg
```

En RHEL/OL:

```bash
sudo dnf install -y perl-DBD-Oracle ora2pg
```

También existen imágenes comunitarias de Docker con Ora2Pg e Instant Client.
Si usas una, revisa su procedencia y fija la versión; no es una imagen oficial
de EDB.

## Configuración

El archivo `ora2pg.conf` de este directorio apunta a los servicios de Docker
Compose (`oracle` y `edb`). Cópialo y ajusta credenciales/hosts:

```bash
cp migration/ora2pg/ora2pg.conf /tmp/ora2pg.conf
```

## Comandos útiles

Assessment y reporte HTML:

```bash
ora2pg -t SHOW_REPORT -c /tmp/ora2pg.conf -o /tmp/ora2pg/report.html
```

Inventario de tablas y columnas:

```bash
ora2pg -t SHOW_TABLE  -c /tmp/ora2pg.conf
ora2pg -t SHOW_COLUMN -c /tmp/ora2pg.conf
```

DDL por tipo de objeto:

```bash
ora2pg -t TYPE      -c /tmp/ora2pg.conf -o /tmp/ora2pg/types.sql
ora2pg -t SEQUENCE  -c /tmp/ora2pg.conf -o /tmp/ora2pg/sequences.sql
ora2pg -t TABLE     -c /tmp/ora2pg.conf -o /tmp/ora2pg/tables.sql
ora2pg -t INDEX     -c /tmp/ora2pg.conf -o /tmp/ora2pg/indexes.sql
ora2pg -t VIEW      -c /tmp/ora2pg.conf -o /tmp/ora2pg/views.sql
ora2pg -t MVIEW     -c /tmp/ora2pg.conf -o /tmp/ora2pg/mviews.sql
ora2pg -t PACKAGE   -c /tmp/ora2pg.conf -o /tmp/ora2pg/packages.sql
ora2pg -t TRIGGER   -c /tmp/ora2pg.conf -o /tmp/ora2pg/triggers.sql
```

Datos:

```bash
ora2pg -t COPY -c /tmp/ora2pg.conf -o /tmp/ora2pg/data.sql
```

Carga del SQL generado:

```bash
psql "host=localhost port=5444 dbname=ventas user=ventas" \
  -v ON_ERROR_STOP=1 -f /tmp/ora2pg/tables.sql
```

## Qué revisar siempre en la salida de Ora2Pg

1. `NUMBER` sin precisión y claves: ¿`numeric`, `bigint` o `integer`?
2. `DATE` de Oracle: ¿se perdió la hora?
3. `CLOB`/`BLOB`: ¿`text`/`bytea` o Large Objects?
4. Objetos, nested tables y VARRAY: normalmente requieren rediseño.
5. Vistas materializadas: no hay `REFRESH FAST ON COMMIT`.
6. Paquetes: compilar con `edb-psql` y revisar `DBMS_*` no soportados.
7. Triggers: validar `INSTEAD OF`, `COMPOUND`, `FOLLOWS` y autonomous.
8. Secuencias: resincronizar con `setval` después de cargar IDs.
9. Índices bitmap, IOT y reverse key: no existen tal cual.
10. Sinónimos, DB links, jobs y directorios: requieren alternativa.

## Ora2Pg vs ETL propio

| Aspecto | Ora2Pg | ETL Python del laboratorio |
|---|---|---|
| DDL | Muy completo | Manual y didáctico |
| Datos | `COPY`, paralelo | `COPY`, un proceso por tabla |
| LOBs | Soporte variable | Control explícito |
| JSON/XML/arrays | Requiere ajustes | Conversión explícita |
| Validación | Limitada | Checksums + pruebas funcionales |
| Curva de aprendizaje | Media/alta | Baja para el alcance del lab |

En una migración real se suele combinar: Ora2Pg para assessment/DDL y un ETL
propio (o herramienta comercial) para datos y validación.
