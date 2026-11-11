# 09. Índices y rendimiento

## Principios

1. Un índice no es “gratis”: ocupa espacio y penaliza escrituras.
2. El optimizador decide con estadísticas; sin `ANALYZE`, los planes son malos.
3. Migrar un índice Oracle no siempre tiene sentido en EPAS; a veces el plan
   cambia y el índice queda sin uso.
4. Mide con datos representativos, no con 10 filas.

## Mapeo de índices

| Oracle | EPAS | Comentario |
|---|---|---|
| B-tree simple | `CREATE INDEX` | Directo |
| B-tree compuesto | `CREATE INDEX (a,b)` | Revisar orden de columnas |
| Único | `CREATE UNIQUE INDEX` | Directo |
| Función `UPPER(col)` | `CREATE INDEX ... (upper(col))` | La expresión debe ser inmutable |
| Función con `CASE` | Índice parcial `WHERE ...` | Más pequeño y claro |
| Descendente | `... (col DESC)` | Directo |
| Bitmap | btree / BRIN / parcial | No hay bitmap |
| IOT | PK + `CLUSTER` | No hay IOT |
| Reverse key | Sin equivalente | Rediseñar |
| Invisible | Sin equivalente | `hypopg`/esquema aparte |
| `INCLUDE` (no Oracle) | `INCLUDE (...)` | Covering index |
| Dominio/texto | GIN/GiST/tsvector | Depende del caso |
| Particionado local | Índice sobre tabla particionada | Se propaga |
| `ONLINE` | `CONCURRENTLY` | No dentro de transacción |

## Índices del laboratorio

### Único funcional

```sql
-- Oracle
CREATE UNIQUE INDEX uq_clientes_email ON clientes (UPPER(email));
-- EPAS
CREATE UNIQUE INDEX uq_clientes_email ON clientes (upper(email));
```

### Índice parcial en lugar de función con CASE

```sql
-- Oracle
CREATE INDEX ix_productos_activos_precio
  ON productos (CASE WHEN activo = 'S' THEN precio END);
-- EPAS
CREATE INDEX ix_productos_activos_precio
  ON productos (precio) WHERE activo = 'S';
```

Ventaja: el índice EPAS no contiene filas inactivas y se usa cuando la consulta
incluye `WHERE activo = 'S'`.

### Covering index

```sql
CREATE INDEX ix_pedidos_estado_include
  ON pedidos (estado) INCLUDE (cliente_id, total);
```

Puede resolver `SELECT cliente_id, total FROM pedidos WHERE estado = 'ENTREGADO'`
sin visitar la tabla (index-only scan), si el visibility map lo permite.

### GIN para arreglos y JSONB

```sql
CREATE INDEX ix_clientes_telefonos_gin ON clientes USING gin (telefonos);
CREATE INDEX ix_productos_atributos_gin
  ON productos USING gin (atributos jsonb_path_ops);
```

Consultas:

```sql
SELECT * FROM clientes WHERE telefonos @> ARRAY['5550000001'];
SELECT * FROM productos WHERE atributos @> '{"color":"rojo"}';
```

### Bitmap → btree

Oracle:

```sql
CREATE BITMAP INDEX bix_pedidos_moneda ON pedidos (moneda);
```

EPAS no tiene bitmap. En el laboratorio se reemplaza por un btree:

```sql
CREATE INDEX ix_pedidos_moneda ON pedidos (moneda);
```

Para baja cardinalidad y tablas grandes, evalúa BRIN o particionamiento; para
consultas analíticas, un scan secuencial puede ser mejor que un índice.

### IOT y reverse key

No hay equivalente exacto. Opciones:

- IOT: `PRIMARY KEY` + `CLUSTER` por esa clave.
- Reverse key: cambiar el diseño o usar hash partitioning.
- Invisible: `hypopg` para simular, o mantener el índice en otro esquema.

## Estadísticas

### Oracle

```sql
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(USER, cascade => TRUE);
-- o
ANALYZE TABLE pedidos COMPUTE STATISTICS;
```

### EPAS

```sql
ANALYZE;
ANALYZE pedidos;
```

El laboratorio ejecuta `ANALYZE` al final de `01_tables.sql`, `02_indexes.sql`
y `09_after_load.sql`. Para tablas grandes, ajusta
`default_statistics_target` y ejecuta `ANALYZE` después de la carga.

## Leer planes

### Oracle

```sql
EXPLAIN PLAN FOR
SELECT * FROM pedidos WHERE cliente_id = 3;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

### EPAS

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT * FROM pedidos WHERE cliente_id = 3;
```

Qué mirar:

- `Seq Scan` vs `Index Scan`.
- `rows` estimadas vs reales.
- `Buffers: shared hit/read`.
- `Sort`/`Hash` con derrame a disco.
- `Nested Loop` vs `Hash Join`.
- `Filter`/`Index Cond`.

Si el plan usa `Seq Scan` en una tabla pequeña, es normal. Forzar el índice
para una demostración:

```sql
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedidos WHERE cliente_id = 3;
RESET enable_seqscan;
```

No dejes `enable_seqscan=off` en producción.

## Consultas de diagnóstico

### Índices sin uso

```sql
SELECT schemaname, relname, indexrelname, idx_scan, idx_tup_read
  FROM pg_stat_user_indexes
 WHERE schemaname = 'ventas'
 ORDER BY idx_scan, pg_relation_size(indexrelid) DESC;
```

### Tamaño de tablas e índices

```sql
SELECT relname AS objeto,
       pg_size_pretty(pg_total_relation_size(oid)) AS total
  FROM pg_class
 WHERE relnamespace = 'ventas'::regnamespace
   AND relkind IN ('r', 'i', 'm')
 ORDER BY pg_total_relation_size(oid) DESC;
```

### Bloat y mantenimiento

```sql
SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum
  FROM pg_stat_user_tables
 WHERE schemaname = 'ventas'
 ORDER BY n_dead_tup DESC;
```

### Progreso de COPY

```sql
SELECT relname, command, type, bytes_processed, tuples_processed
  FROM pg_stat_progress_copy;
```

### Consultas lentas

```sql
SELECT query, calls, mean_exec_time, total_exec_time
  FROM pg_stat_statements
 ORDER BY mean_exec_time DESC
 LIMIT 10;
```

Requiere `pg_stat_statements` en `shared_preload_libraries`. EPAS lo incluye,
pero el laboratorio no lo configura por defecto.

## Benchmark del laboratorio

```bash
make benchmark
```

Genera `migration/reports/benchmark.md` con la mediana de varias iteraciones
para consultas equivalentes. Es indicativo:

- Los datos son pequeños; los planes pueden ser secuenciales.
- Docker y la caché influyen.
- Oracle y EPAS tienen optimizadores distintos.
- No compara hardware justo.

Para un benchmark serio:

1. Usa el mismo hardware y límites de CPU/RAM.
2. Genera datos representativos (millones de filas).
3. Ejecuta `ANALYZE`/estadísticas.
4. Calienta la caché.
5. Ejecuta cada consulta N veces y reporta percentiles.
6. Revisa planes, no solo tiempos.

## Particionamiento

Oracle y EPAS soportan particionamiento por rango/lista/hash, pero el DDL no
es idéntico. El módulo opcional
`sql/oracle/90_optional_partitioning.sql` y
`sql/edb/90_optional_partitioning.sql` muestra el caso.

Diferencias:

- Oracle: índices `LOCAL`/`GLOBAL`, particiones por lista/rango.
- EPAS: índices sobre la tabla padre se propagan; `DEFAULT` partition.
- La poda depende de que el filtro use la clave de partición.
- Las particiones no eliminan la necesidad de índices adecuados.

## Hints

Oracle:

```sql
SELECT /*+ INDEX(p ix_pedidos_cliente_fecha) */ ...
```

EPAS no interpreta los hints de Oracle. `pg_hint_plan` existe como extensión,
pero no está instalada en el laboratorio. Prefiere:

- Reescribir la consulta.
- Ajustar índices/estadísticas.
- Usar `SET` de planificación solo para diagnóstico.

## Paralelismo

EPAS/PostgreSQL puede usar paralelismo:

```sql
SET max_parallel_workers_per_gather = 4;
```

Revisa `EXPLAIN` para ver `Gather`. No actives paralelismo globalmente sin
medir; puede consumir CPU y memoria.

## Connection pooling

Para una aplicación real:

- PgBouncer en modo transaction.
- Ajustar `max_connections`.
- Evitar conexiones por request.
- Usar `prepared statements` con cuidado en transaction pooling.

## Checklist de rendimiento

- [ ] ¿Se ejecutó `ANALYZE` después de la carga?
- [ ] ¿Los índices se crearon después de la carga?
- [ ] ¿Los índices sin uso se revisaron?
- [ ] ¿Las consultas críticas tienen plan estable?
- [ ] ¿Las FKs tienen índices en las columnas hijas?
- [ ] ¿Las tablas grandes están particionadas si aplica?
- [ ] ¿El benchmark usa datos representativos?
- [ ] ¿Se midió el tiempo de la aplicación, no solo SQL?
- [ ] ¿Hay un plan de regresión antes del cutover?

## Siguiente paso

[10-vistas-mv.md](10-vistas-mv.md).
