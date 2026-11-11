-- =============================================================================
-- 90_optional_partitioning.sql  |  Particionamiento en EPAS (opcional)
--
-- Equivalente al módulo Oracle 90_optional_partitioning.sql.
-- EPAS/PostgreSQL soporta particionamiento declarativo por rango, lista y hash.
-- A diferencia de Oracle, no hay índices "locales" explícitos: un índice
-- creado sobre la tabla particionada se propaga a todas las particiones.
-- =============================================================================
SET search_path TO ventas, public;

DROP TABLE IF EXISTS ventas_historicas CASCADE;

CREATE TABLE ventas_historicas (
  venta_id    bigint        NOT NULL,
  pedido_id   bigint        NOT NULL,
  cliente_id  bigint        NOT NULL,
  producto_id bigint        NOT NULL,
  fecha       date          NOT NULL,
  monto       numeric(14,2) NOT NULL,
  CONSTRAINT pk_ventas_historicas PRIMARY KEY (venta_id, fecha)
) PARTITION BY RANGE (fecha);

CREATE TABLE ventas_historicas_p2024
  PARTITION OF ventas_historicas
  FOR VALUES FROM (DATE '2024-01-01') TO (DATE '2025-01-01');

CREATE TABLE ventas_historicas_p2025
  PARTITION OF ventas_historicas
  FOR VALUES FROM (DATE '2025-01-01') TO (DATE '2026-01-01');

CREATE TABLE ventas_historicas_pmax
  PARTITION OF ventas_historicas DEFAULT;

-- Índice particionado: se crea en el padre y se replica en cada partición.
CREATE INDEX ix_vh_fecha ON ventas_historicas (fecha);
CREATE INDEX ix_vh_cliente ON ventas_historicas (cliente_id, fecha);

INSERT INTO ventas_historicas
  (venta_id, pedido_id, cliente_id, producto_id, fecha, monto)
SELECT row_number() OVER (ORDER BY d.detalle_id),
       d.pedido_id,
       p.cliente_id,
       d.producto_id,
       p.fecha_pedido::date,
       d.total_linea
  FROM pedido_detalle d
  JOIN pedidos p ON p.pedido_id = d.pedido_id
 WHERE p.estado = 'ENTREGADO';

ANALYZE ventas_historicas;

-- Verifica la poda de particiones con EXPLAIN.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS ventas_2024
  FROM ventas_historicas
 WHERE fecha >= DATE '2024-01-01' AND fecha < DATE '2025-01-01';

SELECT tableoid::regclass AS particion, count(*)
  FROM ventas_historicas
 GROUP BY tableoid
 ORDER BY 1;
