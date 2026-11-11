-- =============================================================================
-- 10_validation_queries.sql  |  Inspección del destino EPAS
-- =============================================================================
\pset pager off
SET search_path TO ventas, public;

\echo '=== Conteos por tabla ==='
SELECT 'regiones' AS tabla, count(*) AS filas FROM regiones
UNION ALL SELECT 'paises', count(*) FROM paises
UNION ALL SELECT 'clientes', count(*) FROM clientes
UNION ALL SELECT 'direcciones_entrega', count(*) FROM direcciones_entrega
UNION ALL SELECT 'categorias', count(*) FROM categorias
UNION ALL SELECT 'productos', count(*) FROM productos
UNION ALL SELECT 'empleados', count(*) FROM empleados
UNION ALL SELECT 'pedidos', count(*) FROM pedidos
UNION ALL SELECT 'pedido_detalle', count(*) FROM pedido_detalle
UNION ALL SELECT 'pagos', count(*) FROM pagos
UNION ALL SELECT 'auditoria_cambios', count(*) FROM auditoria_cambios
UNION ALL SELECT 'precios_historial', count(*) FROM precios_historial
ORDER BY 1;

\echo '=== Totales por estado ==='
SELECT estado, count(*) AS pedidos, sum(total) AS total
  FROM pedidos
 GROUP BY estado
 ORDER BY estado;

\echo '=== Top 10 productos ==='
SELECT producto_id, nombre, unidades, ingreso, ranking
  FROM vw_top_productos
 ORDER BY ranking;

\echo '=== Ventas mensuales ==='
SELECT mes, pedidos, total FROM vw_ventas_mensuales ORDER BY mes;
SELECT mes, pedidos, total FROM mv_ventas_mensuales ORDER BY mes;

\echo '=== Jerarquía ==='
SELECT nivel, nombre_arbol, manager_id FROM vw_jerarquia_empleados;

\echo '=== Auditoría ==='
SELECT tabla, operacion, count(*) AS eventos
  FROM auditoria_cambios
 GROUP BY tabla, operacion
 ORDER BY tabla, operacion;

\echo '=== Paquetes y funciones ==='
SELECT pkg_ventas.descuento_cliente(3, 10000) AS descuento_cliente_3;
SELECT pkg_ventas.total_pedido(1) AS total_pedido_1;
SELECT pkg_ventas.estado_pedido(2) AS estado_pedido_2;
SELECT pkg_util.formatear_moneda(1234.5) AS moneda;
SELECT pkg_util.es_dia_habil(DATE '2025-01-06') AS lunes_habil;
SELECT fn_calcular_impuesto(1000) AS impuesto;
SELECT fn_promedio_ventas_cliente(3) AS promedio_cliente_3;
SELECT pkg_mantenimiento.contar('pedidos') AS pedidos;

\echo '=== Objetos y secuencias ==='
SELECT relkind, count(*) AS cantidad
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'ventas'
 GROUP BY relkind
 ORDER BY relkind;

SELECT sequencename, last_value
  FROM pg_sequences
 WHERE schemaname = 'ventas'
 ORDER BY sequencename;
