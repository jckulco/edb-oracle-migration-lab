-- =============================================================================
-- 04_indexes.sql  |  Índices Oracle (incluye casos sin equivalente 1:1)
--
-- Casos didácticos:
--   * B-tree simple y compuesto.
--   * Único sobre función UPPER(email)  -> índice funcional en EPAS.
--   * Bitmap                            -> no existe en EPAS.
--   * Índice funcional con CASE         -> índice parcial en EPAS.
--   * Índice descendente                -> soportado en EPAS.
--   * Índice sobre columna virtual      -> índice funcional/expresión.
-- =============================================================================
SET DEFINE OFF

CREATE UNIQUE INDEX uq_clientes_email
  ON clientes (UPPER(email));

CREATE INDEX ix_clientes_segmento
  ON clientes (segmento);

CREATE INDEX ix_clientes_activo_segmento
  ON clientes (activo, segmento);

CREATE INDEX ix_clientes_nombre_mayus
  ON clientes (nombre_mayus);

CREATE INDEX ix_clientes_telefono
  ON clientes (telefono);

CREATE INDEX ix_direcciones_cliente
  ON direcciones_entrega (cliente_id);

CREATE INDEX ix_empleados_manager
  ON empleados (manager_id);

CREATE INDEX ix_productos_categoria_activo
  ON productos (categoria_id, activo);

-- Índice funcional con CASE: solo indexa el precio de productos activos.
CREATE INDEX ix_productos_activos_precio
  ON productos (CASE WHEN activo = 'S' THEN precio END);

CREATE INDEX ix_pedidos_cliente_fecha
  ON pedidos (cliente_id, fecha_pedido DESC);

CREATE INDEX ix_pedidos_estado
  ON pedidos (estado);

CREATE INDEX ix_pedidos_fecha
  ON pedidos (fecha_pedido);

CREATE INDEX ix_pedidos_empleado
  ON pedidos (empleado_id);

-- Bitmap: útil en baja cardinalidad y DML escaso. EPAS no tiene bitmap.
CREATE BITMAP INDEX bix_pedidos_moneda
  ON pedidos (moneda);

CREATE INDEX ix_detalle_producto
  ON pedido_detalle (producto_id);

CREATE INDEX ix_pagos_pedido
  ON pagos (pedido_id);

CREATE INDEX ix_pagos_fecha
  ON pagos (fecha_pago);

CREATE INDEX ix_pagos_metodo
  ON pagos (metodo);

CREATE INDEX ix_historial_producto_fecha
  ON precios_historial (producto_id, fecha);

CREATE INDEX ix_auditoria_usuario_fecha
  ON auditoria_cambios (usuario, fecha);

SHOW ERRORS
