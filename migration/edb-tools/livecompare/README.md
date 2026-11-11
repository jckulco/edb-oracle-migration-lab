# EDB LiveCompare

LiveCompare compara dos o más bases y reporta diferencias fila a fila. La
versión 4.x soporta Oracle como conexión de origen y PostgreSQL/EPAS como
destino.

- Documentación: <https://www.enterprisedb.com/docs/livecompare/latest/>
- Uso CLI: `livecompare archivo.ini`
- Requiere una base de datos de salida para cachear el progreso y los
  reportes.

## Requisitos

1. Binario `livecompare` instalado en el host (o `LIVECOMPARE_BIN`).
2. Base de salida en EPAS. El wrapper crea `livecompare` si no existe.
3. Grants en Oracle para el usuario de comparación:

```sql
GRANT CONNECT, SELECT ANY TABLE, SELECT_CATALOG_ROLE TO ventas;
```

`SELECT ANY TABLE` es amplio. En producción crea un usuario dedicado con solo
los privilegios necesarios.

4. El usuario de EPAS debe poder leer las tablas y crear el esquema
   `livecompare` en la base de salida.

## Ejecución

```bash
# Otorga grants y compara
./scripts/12_livecompare.sh --grant

# Solo valida la configuración (no compara)
./scripts/12_livecompare.sh --dry-run

# Si los grants ya existen
./scripts/12_livecompare.sh
```

El wrapper genera `migration/reports/livecompare/livecompare.ini` con
credenciales y permisos `600`.

## Configuración clave

```ini
[General Settings]
logical_replication_mode = off
max_parallel_workers = 2
oracle_user_tables_only = on
oracle_ignore_unsortable = on
column_intersection = on
difference_tie_breakers = oracle
schema_qualified_table_names = off

[Oracle Connection]
technology = oracle
host = localhost
port = 1521
service = FREEPDB1
user = ventas
password = ...

[EDB Connection]
technology = postgresql
dsn = host=localhost port=5444 dbname=ventas user=ventas password=...
start_query = SET search_path = ventas, public

[Output Connection]
dsn = host=localhost port=5444 dbname=livecompare user=ventas password=...

[Table Filter]
tables = table_name in ('regiones','paises','clientes', ...)
```

- `oracle_user_tables_only = on`: limita a tablas del usuario Oracle.
- `oracle_ignore_unsortable = on`: evita fallos con columnas no ordenables.
- `column_intersection = on`: compara solo columnas comunes.
- `difference_tie_breakers = oracle`: Oracle es la fuente de verdad.
- `schema_qualified_table_names = off`: simplifica nombres; usa
  `start_query` para el `search_path` de EPAS.

## Interpretar resultados

LiveCompare escribe:

- `lc_session_<id>/summary_*.out`
- `lc_session_<id>/differences_*.out`
- `lc_session_<id>/apply_on_the_first_*.sql` (si hay diferencias)
- Tablas `livecompare.vw_table_summary` y `livecompare.vw_differences` en la
  base de salida.

```sql
SELECT * FROM livecompare.vw_table_summary
 ORDER BY session_id DESC LIMIT 5;

SELECT * FROM livecompare.vw_differences
 WHERE session_id = <id>;
```

## Limitaciones

- LiveCompare compara datos, no lógica PL/SQL.
- Con `block_hash`, CLOB/BLOB se limitan a los primeros 2000 caracteres; usa
  `comparison_algorithm = full_row` si necesitas comparar LOBs completos.
- Oracle 11g requiere `oracle_thick_mode = on` e Instant Client.
- Las diferencias pueden ser de formato (timestamps, numeric) o de datos.
- No apliques el DML de corrección sin revisarlo.
- La base de salida no debe ser la misma que la base comparada.

## Referencias

- [Command-line usage](https://www.enterprisedb.com/docs/livecompare/latest/command_line_usage/)
- [Oracle support](https://www.enterprisedb.com/docs/livecompare/latest/oracle_support/)
- [Settings](https://www.enterprisedb.com/docs/livecompare/latest/settings/)
