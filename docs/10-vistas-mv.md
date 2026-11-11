# 10. Vistas y vistas materializadas

## Vistas

### Vistas simples

```sql
CREATE OR REPLACE VIEW vw_clientes_activos AS
SELECT cliente_id, codigo, nombre, email
  FROM clientes
 WHERE activo = 'S'
WITH CHECK OPTION;
```

`WITH CHECK OPTION` impide insertar/actualizar filas que queden fuera del
filtro. EPAS lo soporta.

### Vistas con objetos y funciones

```sql
-- Oracle
SELECT c.direccion.ciudad AS ciudad FROM clientes c;
-- EPAS
SELECT c.dir_ciudad AS ciudad FROM clientes c;
```

```sql
-- Oracle
SELECT TO_CHAR(TRUNC(fecha_pedido,'MM'),'YYYY-MM') AS mes FROM pedidos;
-- EPAS
SELECT to_char(date_trunc('month', fecha_pedido),'YYYY-MM') AS mes FROM pedidos;
```

### Vistas jerárquicas

Oracle:

```sql
SELECT LEVEL, LPAD(' ', (LEVEL-1)*2) || nombre AS nombre_arbol
  FROM empleados
 START WITH manager_id IS NULL
CONNECT BY PRIOR empleado_id = manager_id;
```

EPAS conserva `START WITH`/`CONNECT BY`. Para código nuevo, `WITH RECURSIVE`
es más portable:

```sql
WITH RECURSIVE arbol AS (
  SELECT empleado_id, nombre, manager_id, 1 AS nivel
    FROM empleados
   WHERE manager_id IS NULL
  UNION ALL
  SELECT e.empleado_id, e.nombre, e.manager_id, a.nivel + 1
    FROM empleados e
    JOIN arbol a ON e.manager_id = a.empleado_id
)
SELECT nivel, repeat(' ', (nivel-1)*2) || nombre AS nombre_arbol
  FROM arbol
 ORDER BY nivel, nombre;
```

### Top N

```sql
-- Oracle
SELECT * FROM (
  SELECT ... FROM pedidos ORDER BY fecha_pedido DESC
) WHERE ROWNUM <= 10;

-- EPAS
SELECT ... FROM pedidos ORDER BY fecha_pedido DESC LIMIT 10;
```

### Vistas de solo lectura

Oracle permite `WITH READ ONLY`; PostgreSQL/EPAS no tiene esa cláusula.
Alternativas:

- No otorgar `INSERT/UPDATE/DELETE` sobre la vista.
- Usar una vista sobre una función/CTE.
- Usar un trigger `INSTEAD OF` que rechace cambios (poco práctico).

## Vistas materializadas

### Oracle

```sql
CREATE MATERIALIZED VIEW mv_ventas_mensuales
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT TO_CHAR(TRUNC(fecha_pedido,'MM'),'YYYY-MM') AS mes,
       COUNT(*) AS pedidos,
       SUM(total) AS total
  FROM pedidos
 WHERE estado <> 'CANCELADO'
 GROUP BY TRUNC(fecha_pedido,'MM');
```

### EPAS

```sql
CREATE MATERIALIZED VIEW mv_ventas_mensuales AS
SELECT to_char(date_trunc('month', fecha_pedido),'YYYY-MM') AS mes,
       COUNT(*) AS pedidos,
       SUM(total) AS total
  FROM pedidos
 WHERE estado <> 'CANCELADO'
 GROUP BY date_trunc('month', fecha_pedido)
WITH DATA;

CREATE UNIQUE INDEX ux_mv_ventas_mensuales ON mv_ventas_mensuales (mes);
```

### Refresco

```sql
REFRESH MATERIALIZED VIEW mv_ventas_mensuales;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_mensuales;
```

- `CONCURRENTLY` requiere un índice único y no puede ejecutarse dentro de una
  transacción.
- El refresco completo bloquea la MV mientras dura.
- El laboratorio usa `pkg_mantenimiento.refrescar_mv('mv_ventas_mensuales')`.

### Lo que no existe en EPAS

| Oracle | EPAS |
|---|---|
| `REFRESH FAST` | No |
| `REFRESH ON COMMIT` | No |
| Materialized view logs | No equivalente directo |
| Query rewrite automático | Limitado; no como Oracle |
| `DBMS_MVIEW.REFRESH` | `REFRESH MATERIALIZED VIEW` |

Si necesitas datos “casi en tiempo real”:

1. Refresco programado (pg_cron, scheduler externo).
2. Tabla de agregados actualizada por triggers (cuidado con coste).
3. CDC (Debezium, logical replication) hacia una tabla.
4. Vista normal si el rendimiento lo permite.
5. `REFRESH MATERIALIZED VIEW CONCURRENTLY` cada N minutos.

### Programar el refresco

Con `pg_cron` (si está instalado):

```sql
SELECT cron.schedule(
  'refresh_mv_ventas',
  '*/15 * * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_mensuales$$
);
```

Sin `pg_cron`, usa un cron externo:

```bash
*/15 * * * * psql "host=localhost port=5444 dbname=ventas user=ventas" \
  -c "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_mensuales"
```

## Estrategia de migración de vistas

1. Migrar primero las vistas simples.
2. Reescribir funciones Oracle (`TRUNC`, `NVL`, `DECODE`) a estándar cuando sea
   posible.
3. Validar el resultado con las mismas consultas.
4. Medir las vistas usadas por reportes.
5. Para MVs, definir frecuencia y tolerancia a datos obsoletos.
6. Documentar las vistas que no se pueden migrar 1:1.

## Pruebas

```sql
-- Comparar conteos y agregados
SELECT COUNT(*) FROM vw_clientes_activos;
SELECT mes, pedidos, total FROM vw_ventas_mensuales ORDER BY mes;
SELECT * FROM vw_top_productos ORDER BY ranking;
```

El script `migration/config/functional_tests.yaml` incluye pruebas para
`vw_clientes_activos`, `vw_jerarquia_empleados`, `vw_top_productos`,
`vw_ultimos_pedidos` y `mv_ventas_mensuales`.

## Checklist de vistas y MV

- [ ] ¿Cada vista compila en EPAS?
- [ ] ¿Los objetos/funciones Oracle se reescribieron?
- [ ] ¿`ROWNUM` se cambió por `LIMIT` donde aplica?
- [ ] ¿La MV tiene índice único si se refresca `CONCURRENTLY`?
- [ ] ¿Hay un job de refresco?
- [ ] ¿Se midió el coste del refresco?
- [ ] ¿La aplicación tolera datos desactualizados?
- [ ] ¿Las pruebas funcionales cubren las vistas?

## Siguiente paso

[11-triggers-secuencias.md](11-triggers-secuencias.md).
