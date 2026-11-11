-- =============================================================================
-- 90_optional_partitioning.sql  |  Módulo opcional de particionamiento
--
-- NO forma parte de la carga por defecto. Oracle Database Free 23ai incluye
-- particionamiento, pero conviene verificar la edición/versión antes de usarlo.
--
-- EPAS soporta particionamiento declarativo, pero el mapeo no es automático:
--   PARTITION BY RANGE (fecha)  ->  PARTITION BY RANGE (fecha)
--   Índice LOCAL                ->  índice en cada partición o índice global
--   Partición por lista         ->  PARTITION BY LIST
--
-- Ejecuta este archivo solo si quieres practicar el caso avanzado.
-- =============================================================================
SET DEFINE OFF

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE ventas_historicas PURGE';
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE ventas_historicas (
  venta_id    NUMBER(12)   NOT NULL,
  pedido_id   NUMBER(12)   NOT NULL,
  cliente_id  NUMBER(10)   NOT NULL,
  producto_id NUMBER(10)   NOT NULL,
  fecha       DATE         NOT NULL,
  monto       NUMBER(14,2) NOT NULL,
  CONSTRAINT pk_ventas_historicas PRIMARY KEY (venta_id, fecha)
)
PARTITION BY RANGE (fecha) (
  PARTITION p2024 VALUES LESS THAN (DATE '2025-01-01'),
  PARTITION p2025 VALUES LESS THAN (DATE '2026-01-01'),
  PARTITION pmax  VALUES LESS THAN (MAXVALUE)
);

CREATE INDEX ix_vh_fecha ON ventas_historicas (fecha) LOCAL;
CREATE INDEX ix_vh_cliente ON ventas_historicas (cliente_id, fecha) LOCAL;

INSERT INTO ventas_historicas
  (venta_id, pedido_id, cliente_id, producto_id, fecha, monto)
SELECT ROW_NUMBER() OVER (ORDER BY d.detalle_id),
       d.pedido_id,
       p.cliente_id,
       d.producto_id,
       CAST(p.fecha_pedido AS DATE),
       d.total_linea
  FROM pedido_detalle d
  JOIN pedidos p ON p.pedido_id = d.pedido_id
 WHERE p.estado = 'ENTREGADO';

COMMIT;

-- Consulta con poda de partición (revisa el plan con EXPLAIN PLAN).
SELECT COUNT(*) AS ventas_2024
  FROM ventas_historicas PARTITION (p2024);

SELECT partition_name, num_rows
  FROM user_tab_partitions
 WHERE table_name = 'VENTAS_HISTORICAS'
 ORDER BY partition_position;

PROMPT Módulo opcional de particionamiento cargado.
