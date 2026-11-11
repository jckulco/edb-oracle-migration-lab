# 21. EDB LiveCompare

## Qué es

LiveCompare compara dos o más bases y reporta diferencias fila a fila. La
versión 4.x soporta Oracle como conexión de origen y PostgreSQL/EPAS como
destino.

- Documentación: <https://www.enterprisedb.com/docs/livecompare/latest/>
- CLI: `livecompare archivo.ini`
- Salida: sesiones `lc_session_<id>/`, tablas en la base de salida.

## Requisitos

1. **Binario** `livecompare` instalado en el host.
2. **Base de salida** en EPAS. El wrapper crea `livecompare` si no existe.
3. **Grants Oracle**:

```sql
GRANT CONNECT, SELECT ANY TABLE, SELECT_CATALOG_ROLE TO ventas;
```

`SELECT ANY TABLE` es amplio. En producción usa un usuario dedicado.

4. El usuario EPAS debe poder leer las tablas y crear el esquema
   `livecompare` en la base de salida.

## Ejecución

```bash
make tools-check
make livecompare-dry-run   # valida INI y conexiones
make livecompare-grant     # grants + comparación
make livecompare           # si los grants ya existen
```

El wrapper:

1. Espera a Oracle y EPAS.
2. Crea la base `livecompare` si falta.
3. Genera `migration/reports/livecompare/livecompare.ini` con permisos `600`.
4. Ejecuta `livecompare ... --dry-run` o la comparación completa.
5. Deja logs y sesiones en `migration/reports/livecompare/`.

## Configuración

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
tables = table_name in ('regiones','paises', ...)
```

### Por qué estas opciones

- `schema_qualified_table_names = off`: evita comparar `VENTAS.CLIENTES`
  contra `ventas.clientes`; el `search_path` resuelve el lado EPAS.
- `oracle_user_tables_only = on`: limita a tablas del usuario Oracle.
- `oracle_ignore_unsortable = on`: evita fallos con columnas no ordenables.
- `column_intersection = on`: compara solo columnas comunes; útil si el DDL
  difiere en columnas generadas.
- `difference_tie_breakers = oracle`: Oracle es la fuente de verdad.

## Interpretar la salida

```text
Saved file lc_session_5/summary_....out
Found 0 inconsistent rows in 0 tables.
```

Si hay diferencias:

```text
Found 4 inconsistent rows in 1 tables.
Saved file lc_session_6/differences_....out
Script lc_session_6/apply_on_the_first_....sql was generated...
```

Consultas:

```sql
SELECT * FROM livecompare.vw_table_summary
 ORDER BY session_id DESC LIMIT 5;

SELECT * FROM livecompare.vw_differences
 WHERE session_id = 6;

SELECT * FROM livecompare.vw_consensus
 WHERE session_id = 6;
```

## Diferencias con `validate.py`

| Aspecto | LiveCompare | `validate.py` |
|---|---|---|
| Herramienta | EDB comercial | Python del laboratorio |
| Cobertura | Filas, varias bases | Filas + pruebas funcionales |
| Checksum | Block/row hash común | SHA-256 canónico propio |
| LOBs | Limitaciones en block_hash | Control explícito |
| Reportes | Sesiones y tablas | Markdown/JSON |
| Coste | Licencia | Gratis |

Usa ambos: LiveCompare aporta la mirada de la herramienta comercial;
`validate.py` aporta pruebas de negocio y reportes versionables.

## Limitaciones

- Compara datos, no lógica PL/SQL.
- Con `block_hash`, CLOB/BLOB se limitan a los primeros 2000 caracteres.
- Oracle 11g requiere thick mode + Instant Client.
- Diferencias de formato (`numeric`, timestamps) pueden aparecer como
  diferencias; revisa el detalle antes de “corregir”.
- No apliques el DML de corrección sin revisión.
- La base de salida no debe ser la misma que la comparada.

## Checklist

- [ ] `livecompare` está en PATH.
- [ ] La base de salida existe y es distinta de `ventas`.
- [ ] Los grants Oracle están aplicados.
- [ ] `--dry-run` muestra las tablas esperadas.
- [ ] La comparación termina sin diferencias (o las diferencias están
      explicadas).
- [ ] Los reportes se archivaron.

## Referencias

- <https://www.enterprisedb.com/docs/livecompare/latest/command_line_usage/>
- <https://www.enterprisedb.com/docs/livecompare/latest/oracle_support/>
- <https://www.enterprisedb.com/docs/livecompare/latest/settings/>
