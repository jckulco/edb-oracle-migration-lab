-- =============================================================================
-- 12_validation_queries.sql  |  Consultas de inspección en Oracle
--
-- No sustituyen la validación automática de migration/etl/validate.py; son
-- el punto de partida para revisar el estado del origen antes de migrar.
-- =============================================================================
SET PAGESIZE 200
SET LINESIZE 220
SET FEEDBACK OFF
SET DEFINE OFF
ALTER SESSION SET TIME_ZONE = 'UTC';

PROMPT === Conteos por tabla ===
SELECT 'REGIONES' AS tabla, COUNT(*) AS filas FROM regiones
UNION ALL SELECT 'PAISES', COUNT(*) FROM paises
UNION ALL SELECT 'CLIENTES', COUNT(*) FROM clientes
UNION ALL SELECT 'DIRECCIONES', COUNT(*) FROM direcciones_entrega
UNION ALL SELECT 'CATEGORIAS', COUNT(*) FROM categorias
UNION ALL SELECT 'PRODUCTOS', COUNT(*) FROM productos
UNION ALL SELECT 'EMPLEADOS', COUNT(*) FROM empleados
UNION ALL SELECT 'PEDIDOS', COUNT(*) FROM pedidos
UNION ALL SELECT 'PEDIDO_DETALLE', COUNT(*) FROM pedido_detalle
UNION ALL SELECT 'PAGOS', COUNT(*) FROM pagos
UNION ALL SELECT 'AUDITORIA', COUNT(*) FROM auditoria_cambios
UNION ALL SELECT 'PRECIOS_HISTORIAL', COUNT(*) FROM precios_historial
ORDER BY 1;

PROMPT === Totales por estado ===
SELECT estado, COUNT(*) AS pedidos, SUM(total) AS total
  FROM pedidos
 GROUP BY estado
 ORDER BY estado;

PROMPT === Top 10 productos por unidades ===
SELECT producto_id, nombre, unidades, ingreso, ranking
  FROM vw_top_productos
 ORDER BY ranking;

PROMPT === Ventas mensuales (vista y MV) ===
SELECT mes, pedidos, total FROM vw_ventas_mensuales ORDER BY mes;
SELECT mes, pedidos, total FROM mv_ventas_mensuales ORDER BY mes;

PROMPT === Jerarquía de empleados ===
SELECT nivel, nombre_arbol, ruta FROM vw_jerarquia_empleados ORDER BY nivel, nombre_arbol;

PROMPT === Auditoría por tabla/operación ===
SELECT tabla, operacion, COUNT(*) AS eventos
  FROM auditoria_cambios
 GROUP BY tabla, operacion
 ORDER BY tabla, operacion;

PROMPT === Pruebas rápidas de paquetes y funciones ===
SELECT pkg_ventas.descuento_cliente(3, 10000) AS descuento_cliente_3 FROM dual;
SELECT pkg_ventas.total_pedido(1) AS total_pedido_1 FROM dual;
SELECT pkg_ventas.estado_pedido(2) AS estado_pedido_2 FROM dual;
SELECT pkg_util.formatear_moneda(1234.5) AS moneda FROM dual;
SELECT pkg_util.es_dia_habil(DATE '2025-01-06') AS lunes_habil FROM dual;
SELECT fn_calcular_impuesto(1000) AS impuesto FROM dual;
SELECT fn_promedio_ventas_cliente(3) AS promedio_cliente_3 FROM dual;
SELECT pkg_mantenimiento.contar('PEDIDOS') AS pedidos FROM dual;

PROMPT === Objetos del esquema ===
SELECT object_type, COUNT(*) AS cantidad
  FROM user_objects
 GROUP BY object_type
 ORDER BY object_type;
