-- =============================================================================
-- 09_after_load.sql  |  Resincronización de secuencias y estadísticas
--
-- Las secuencias Oracle y las identidades se cargan con valores explícitos.
-- Para evitar colisiones en las siguientes inserciones, se ajusta su valor
-- al máximo actual + 1. setval(..., false) hace que el próximo nextval
-- devuelva exactamente ese valor.
-- =============================================================================
SET search_path TO ventas, public;

SELECT setval('seq_clientes',
              COALESCE((SELECT MAX(cliente_id) FROM clientes), 0) + 1, false);
SELECT setval('seq_direcciones',
              COALESCE((SELECT MAX(direccion_id) FROM direcciones_entrega), 0) + 1, false);
SELECT setval('seq_pedidos',
              COALESCE((SELECT MAX(pedido_id) FROM pedidos), 0) + 1, false);
SELECT setval('seq_pagos',
              COALESCE((SELECT MAX(pago_id) FROM pagos), 0) + 1, false);
SELECT setval('seq_historial',
              COALESCE((SELECT MAX(historial_id) FROM precios_historial), 0) + 1, false);

SELECT setval(pg_get_serial_sequence('productos', 'producto_id'),
              COALESCE((SELECT MAX(producto_id) FROM productos), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('pedido_detalle', 'detalle_id'),
              COALESCE((SELECT MAX(detalle_id) FROM pedido_detalle), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('auditoria_cambios', 'auditoria_id'),
              COALESCE((SELECT MAX(auditoria_id) FROM auditoria_cambios), 0) + 1, false);

-- Refresco inicial de la vista materializada.
REFRESH MATERIALIZED VIEW mv_ventas_mensuales;

-- Estadísticas para el optimizador.
ANALYZE;

-- Resumen rápido de la carga.
SELECT 'regiones' AS tabla, count(*) FROM regiones
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
