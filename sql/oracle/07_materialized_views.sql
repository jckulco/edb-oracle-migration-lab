-- =============================================================================
-- 07_materialized_views.sql  |  Vista materializada Oracle
--
-- Se crea con REFRESH COMPLETE ON DEMAND para que la comparación sea justa:
-- EPAS no soporta REFRESH FAST ON COMMIT ni logs de vista materializada
-- equivalentes. El refresco se invoca con pkg_mantenimiento.refrescar_mv.
-- =============================================================================
SET DEFINE OFF

CREATE MATERIALIZED VIEW mv_ventas_mensuales
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT TO_CHAR(TRUNC(p.fecha_pedido, 'MM'), 'YYYY-MM') AS mes,
       COUNT(*) AS pedidos,
       SUM(p.total) AS total
  FROM pedidos p
 WHERE p.estado <> 'CANCELADO'
 GROUP BY TRUNC(p.fecha_pedido, 'MM');

CREATE UNIQUE INDEX ux_mv_ventas_mensuales
  ON mv_ventas_mensuales (mes);

COMMENT ON MATERIALIZED VIEW mv_ventas_mensuales IS
  'Agregado mensual; en EPAS se refresca bajo demanda';

SHOW ERRORS
