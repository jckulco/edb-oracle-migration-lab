# 07. Migración de datos

## Estrategias posibles

| Estrategia | Cuándo usarla | Ventajas | Riesgos |
|---|---|---|---|
| `INSERT ... SELECT` por DB link | Volúmenes pequeños, mismo DBA | Simple | Lento, dependencia de red |
| Ora2Pg `COPY` | Volúmenes grandes, esquema estable | Maduro, paralelizable | Menos control sobre tipos especiales |
| ETL propio + `COPY` | LOBs, JSON, XML, arrays, validación fina | Control y trazabilidad | Más código que mantener |
| Herramienta comercial EDB | Proyectos grandes | Soporte y automatización | Coste, lock-in |
| Export/Import lógico | Casos puntuales | Conocido | No traduce dialectos |

El laboratorio usa **ETL propio** para enseñar el detalle y deja Ora2Pg como
complemento ([16-ora2pg.md](16-ora2pg.md)).

## Por qué python-oracledb thin

`python-oracledb` en modo thin:

- No requiere Oracle Instant Client.
- Funciona en Linux, macOS y Windows.
- Soporta conexión, cursores, LOBs y tipos habituales.
- Devuelve `str`/`bytes` para CLOB/BLOB si se configura `fetch_lobs=False`.
- Devuelve `Decimal` para `NUMBER` si se configura `fetch_decimals=True`.

En el ETL:

```python
oracledb.defaults.fetch_lobs = False
oracledb.defaults.fetch_decimals = True
conn = oracledb.connect(user=..., password=..., dsn=...)
cur.execute("ALTER SESSION SET TIME_ZONE = 'UTC'")
```

## Arquitectura del ETL

```text
migration/config/migration.yaml
        │
        ▼
┌──────────────────┐     SELECT      ┌──────────────┐
│ Oracle (origen)  │ ──────────────► │ extract_load │
└──────────────────┘                 │  normalize   │
                                     │  COPY        │
                                     ▼              │
                              ┌──────────────┐      │
                              │ EPAS (destino)│ ◄────┘
                              └──────────────┘
```

Archivos:

| Archivo | Responsabilidad |
|---|---|
| `migration/config/migration.yaml` | Orden, columnas, SELECT Oracle, PK y secuencias |
| `migration/etl/config.py` | Carga de `.env` y del manifiesto |
| `migration/etl/oracle_source.py` | Conexión y lectura Oracle |
| `migration/etl/pg_target.py` | Conexión, COPY, truncate y consultas |
| `migration/etl/type_mapping.py` | Normalización y canonicalización |
| `migration/etl/extract_load.py` | Orquestador de la carga |
| `migration/etl/resync_sequences.py` | Ajuste de secuencias/identidades |

## El manifiesto

Cada tabla declara:

```yaml
- name: clientes
  order: 30
  pk: [cliente_id]
  columns:
    - cliente_id
    - codigo
    - nombre
    - dir_calle
    - telefonos
    - datos_extra
  select: |
    SELECT c.cliente_id, c.codigo, c.nombre,
           c.direccion.calle AS dir_calle,
           (SELECT LISTAGG(column_value, '|')
              WITHIN GROUP (ORDER BY column_value)
              FROM TABLE(c.telefonos)) AS telefonos,
           c.datos_extra
      FROM clientes c
```

- `columns`: columnas destino, en el mismo orden que el SELECT.
- `select`: consulta Oracle que produce exactamente esas columnas.
- `pk`: para ordenar/comparar en la validación.
- `order`: orden topológico (padres antes que hijos).

El manifiesto es la **fuente de verdad** de la migración. Si agregas una
columna, actualiza ambos lados y el DDL.

## Comandos

```bash
# Carga completa (trunca el destino)
make migrate

# Solo contar filas, sin escribir
make migrate -- --dry-run

# Subconjunto
make migrate -- --tables clientes,pedidos

# Sin truncar (solo si el destino está vacío o controlas los duplicados)
make migrate -- --no-truncate
```

> `make migrate` agrega `--truncate` automáticamente salvo con `--dry-run`.

Salida típica:

```text
Origen : Oracle localhost:1521/FREEPDB1 (schema VENTAS)
Destino: EPAS localhost:5444/ventas (schema ventas)
Tablas : regiones, paises, clientes, ...
------------------------------------------------------------------------------
Cargando regiones... 4 filas en 0.01s
...
Total cargado: 1543 filas
Reporte: migration/reports/data_load.json
```

El número exacto depende de la semilla y de los triggers.

## Normalización de tipos

| Columna destino | Valor Oracle | Transformación |
|---|---|---|
| `bigint` | `NUMBER` | `int()` |
| `numeric` | `NUMBER` | `Decimal` |
| `timestamp(0)` | `DATE` | `datetime` |
| `timestamp(6)` | `TIMESTAMP` | `datetime` |
| `timestamptz` | `TIMESTAMP WITH [LOCAL] TIME ZONE` | adjuntar/convertir a UTC |
| `interval` | `INTERVAL DAY TO SECOND` | `timedelta` |
| `text` | `CLOB` / `LONG` | `str` |
| `bytea` | `BLOB` / `RAW` | `bytes` |
| `xml` | `XMLTYPE.getClobVal()` | `str` |
| `jsonb` | `CLOB` JSON | `json.loads` → `dict` |
| `text[]` | `LISTAGG(..., '|')` | `split('|')` |
| `real` | `BINARY_FLOAT` | `float` |

`normalize_value()` decide según el tipo **destino**, no según el nombre de la
columna. Así el ETL y la validación usan la misma regla.

### LOBs

- `fetch_lobs=False` evita objetos `LOB` y entrega `str`/`bytes`.
- Para CLOB/BLOB grandes, considera streaming con `LOB.read()` y `COPY` en
  bloques; el laboratorio los mantiene pequeños para simplificar.
- `bytea` tiene un límite práctico de 1 GB por valor; para archivos mayores,
  usa Large Objects o almacenamiento externo.

### JSON

- El origen es `CLOB` con `CHECK ... IS JSON`.
- `json.loads` valida el documento.
- `psycopg` adapta `dict` a `jsonb` con `Jsonb`.
- La validación ordena las claves para comparar.

### XML

- `XMLTYPE.getClobVal()` devuelve el documento como texto.
- El destino `xml` valida que esté bien formado.
- La validación compara el texto sin espacios en los extremos; no normaliza
  nombres de espacios ni comentarios.

### Arreglos

- `LISTAGG(column_value, '|')` produce `"555...|777..."`.
- El ETL divide por `|` y carga `text[]`.
- La validación serializa el arreglo a JSON canónico.

### Timestamps

- La sesión Oracle se fija en UTC.
- `TIMESTAMP WITH LOCAL TIME ZONE` se devuelve como fecha/hora en UTC.
- El ETL adjunta `tzinfo=UTC` y EPAS almacena `timestamptz`.
- La validación compara en UTC.

## Orden de carga y claves foráneas

El manifiesto ordena:

```text
regiones → paises → clientes → direcciones → categorias → productos
→ empleados → pedidos → pedido_detalle → pagos → auditoria → historial
```

Si las FKs ya existen, este orden las respeta. Si se cargan tablas en paralelo,
hay que desactivar FKs o usar `session_replication_role = replica` (superusuario)
y validar después. El laboratorio opta por el orden secuencial.

## Índices, FKs y triggers

La estrategia es:

1. Crear tablas sin índices secundarios ni FKs.
2. Cargar con `COPY`.
3. Crear índices.
4. Crear FKs `NOT VALID` y validarlas.
5. Crear vistas, MV, paquetes y triggers.
6. Resincronizar secuencias y refrescar MV.

Así se evita:

- Duplicar auditoría por triggers durante la carga.
- Pagar el coste de mantener índices en cada `COPY`.
- Bloquear la tabla al crear FKs.

## Secuencias e identidades

El ETL inserta IDs explícitos. Las secuencias Oracle y las identidades EPAS no
avanzan automáticamente. Después de la carga:

```sql
SELECT setval('seq_pedidos',
              COALESCE((SELECT MAX(pedido_id) FROM pedidos), 0) + 1,
              false);
```

`false` significa que el próximo `nextval` devuelve exactamente ese valor.

`09_after_load.sql` hace esto para todas las secuencias e identidades. El
script `resync_sequences.py` permite repetirlo por separado.

## Reporte de carga

`migration/reports/data_load.json` contiene:

```json
{
  "generated_at": "2026-11-10T21:00:00+00:00",
  "oracle_dsn": "localhost:1521/FREEPDB1",
  "oracle_schema": "VENTAS",
  "edb_schema": "ventas",
  "dry_run": false,
  "tables": [
    {"table": "regiones", "rows_read": 4, "rows_loaded": 4, "seconds": 0.01}
  ],
  "total_rows": 1543
}
```

Úsalo para comparar con la validación. Si `rows_read != rows_loaded`, algo
falló antes de hacer commit.

## Reintentos e idempotencia

- `--truncate` limpia todas las tablas del manifiesto con
  `TRUNCATE ... RESTART IDENTITY` y luego carga.
- Cada tabla se confirma al terminar; si una falla, las anteriores quedan
  cargadas. Vuelve a ejecutar con `--truncate`.
- Si el esquema tiene FKs y cargas un subconjunto, el `TRUNCATE` puede fallar.
  Usa el conjunto completo o elimina FKs temporalmente.
- Si un `COPY` falla por un valor, el mensaje indica tabla/columna; corrige el
  dato o el mapeo y reintenta.

## Volúmenes grandes

Para tablas de millones de filas:

1. Aumenta `ETL_BATCH_SIZE` (por ejemplo 5000) y usa `fetchmany`.
2. Considera `COPY ... FROM STDIN` en binario (`cursor.copy(..., binary=True)`)
   para tipos homogéneos.
3. Carga en paralelo por tabla si no hay FKs.
4. Crea índices después y con `maintenance_work_mem` alto.
5. Evita `INSERT` fila por fila.
6. Desactiva `archive_mode`/`synchronous_commit` solo en el destino de staging
   y con criterio.
7. Usa tablas UNLOGGED para staging y luego `INSERT INTO ... SELECT`.
8. Monitorea `pg_stat_progress_copy`.

El laboratorio no implementa paralelismo para mantenerlo legible.

## Errores frecuentes

| Error | Causa | Solución |
|---|---|---|
| `invalid input syntax for type json` | CLOB no es JSON válido | Revisar el dato; validar con `IS JSON` |
| `invalid XML document` | XML mal formado | Exportar con `getClobVal()` y validar |
| `malformed array literal` | Separador incorrecto | Usar `normalize_value` y `text[]` |
| `numeric field overflow` | Precisión insuficiente | Ajustar `numeric(p,s)` |
| `value too long for type character varying(n)` | `VARCHAR2 BYTE` vs caracteres | Ampliar o revisar semántica |
| `duplicate key value violates unique constraint` | No se truncó o secuencia desfasada | `--truncate` y `setval` |
| `FK violation` | Orden de carga incorrecto | Respetar `order` del manifiesto |
| `connection refused` | Contenedor no healthy | `make ps`, `make logs` |
| `ORA-12541` | Listener no listo | Esperar healthcheck |
| `DPY-6005` | Oracle no accesible | Revisar `ORACLE_DSN` y puerto |

## Ora2Pg para datos

Si usas Ora2Pg:

```bash
ora2pg -t COPY -c migration/ora2pg/ora2pg.conf -o /tmp/data.sql
```

Revisa el SQL generado antes de aplicarlo. Ora2Pg puede paralelizar y manejar
volúmenes grandes, pero no conoce tus reglas de negocio ni tu estrategia de
secuencias/triggers.

## Checklist de datos

- [ ] El manifiesto cubre todas las tablas.
- [ ] El SELECT Oracle produce las columnas destino en orden.
- [ ] Los tipos destino existen y las columnas coinciden.
- [ ] El orden respeta FKs.
- [ ] Los triggers se crean después de la carga.
- [ ] Las secuencias se resincronizan.
- [ ] El reporte de carga cuadra con los conteos.
- [ ] La validación de checksums pasa.
- [ ] Las pruebas funcionales pasan.
- [ ] Hay un plan de reintento.

## Siguiente paso

[08-plsql-a-epas.md](08-plsql-a-epas.md): la lógica que no se migra con un
`COPY`.
