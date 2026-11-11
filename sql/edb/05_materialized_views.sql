-- =============================================================================
-- 05_materialized_views.sql  |  Vista materializada en EPAS
--
-- Diferencias clave frente a Oracle:
--   * No existe REFRESH FAST ni REFRESH ON COMMIT.
--   * El refresco es COMPLETE y se hace con REFRESH MATERIALIZED VIEW.
--   * REFRESH ... CONCURRENTLY requiere un índice único (lo creamos).
--   * La programación se hace con pg_cron, un job externo o el scheduler.
-- =============================================================================
SET search_path TO ventas, public;

DROP MATERIALIZED VIEW IF EXISTS mv_ventas_mensuales;

CREATE MATERIALIZED VIEW mv_ventas_mensuales AS
SELECT to_char(date_trunc('month', p.fecha_pedido), 'YYYY-MM') AS mes,
       COUNT(*) AS pedidos,
       SUM(p.total) AS total
  FROM pedidos p
 WHERE p.estado <> 'CANCELADO'
 GROUP BY date_trunc('month', p.fecha_pedido)
 WITH DATA;

CREATE UNIQUE INDEX ux_mv_ventas_mensuales
  ON mv_ventas_mensuales (mes);

COMMENT ON MATERIALIZED VIEW mv_ventas_mensuales IS
  'Agregado mensual; refrescar con pkg_mantenimiento.refrescar_mv';

ANALYZE;
