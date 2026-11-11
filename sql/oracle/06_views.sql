-- =============================================================================
-- 06_views.sql  |  Vistas Oracle
--
-- Se incluyen vistas simples, con CHECK OPTION, agregadas, jerárquicas,
-- analíticas y con ROWNUM. Cada una tiene su versión EPAS en sql/edb/04_views.sql.
-- =============================================================================
SET DEFINE OFF

CREATE OR REPLACE VIEW vw_clientes_activos AS
SELECT c.cliente_id,
       c.codigo,
       c.nombre,
       c.email,
       c.telefono,
       c.segmento,
       c.limite_credito,
       c.saldo,
       c.direccion.ciudad   AS ciudad,
       c.direccion.pais     AS pais
  FROM clientes c
 WHERE c.activo = 'S'
WITH CHECK OPTION;

CREATE OR REPLACE VIEW vw_resumen_pedidos AS
SELECT p.pedido_id,
       p.fecha_pedido,
       c.nombre AS cliente,
       p.estado,
       p.moneda,
       p.total,
       COUNT(d.detalle_id) AS lineas,
       NVL(SUM(d.cantidad), 0) AS unidades
  FROM pedidos p
  JOIN clientes c ON c.cliente_id = p.cliente_id
  LEFT JOIN pedido_detalle d ON d.pedido_id = p.pedido_id
 GROUP BY p.pedido_id, p.fecha_pedido, c.nombre, p.estado, p.moneda, p.total;

CREATE OR REPLACE VIEW vw_ventas_mensuales AS
SELECT TO_CHAR(TRUNC(p.fecha_pedido, 'MM'), 'YYYY-MM') AS mes,
       COUNT(*) AS pedidos,
       SUM(p.total) AS total
  FROM pedidos p
 WHERE p.estado <> 'CANCELADO'
 GROUP BY TRUNC(p.fecha_pedido, 'MM');

CREATE OR REPLACE VIEW vw_jerarquia_empleados AS
SELECT LEVEL AS nivel,
       LPAD(' ', (LEVEL - 1) * 2) || e.nombre AS nombre_arbol,
       e.empleado_id,
       e.manager_id,
       SYS_CONNECT_BY_PATH(e.nombre, ' / ') AS ruta
  FROM empleados e
 START WITH e.manager_id IS NULL
CONNECT BY PRIOR e.empleado_id = e.manager_id
 ORDER SIBLINGS BY e.nombre;

CREATE OR REPLACE VIEW vw_top_productos AS
SELECT *
  FROM (
    SELECT p.producto_id,
           p.nombre,
           SUM(d.cantidad) AS unidades,
           SUM(d.total_linea) AS ingreso,
           RANK() OVER (ORDER BY SUM(d.cantidad) DESC) AS ranking
      FROM productos p
      JOIN pedido_detalle d ON d.producto_id = p.producto_id
     GROUP BY p.producto_id, p.nombre
  ) t
 WHERE ranking <= 10;

-- ROWNUM: patrón Oracle para "top N". EPAS usa LIMIT.
CREATE OR REPLACE VIEW vw_ultimos_pedidos AS
SELECT *
  FROM (
    SELECT p.pedido_id,
           p.fecha_pedido,
           c.nombre AS cliente,
           p.estado,
           p.total
      FROM pedidos p
      JOIN clientes c ON c.cliente_id = p.cliente_id
     ORDER BY p.fecha_pedido DESC
  ) t
 WHERE ROWNUM <= 10;

SHOW ERRORS
