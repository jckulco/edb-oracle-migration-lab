-- =============================================================================
-- 02_indexes.sql  |  Índices EPAS equivalentes y mejoras
--
-- Mapeo:
--   B-tree Oracle                 -> btree
--   Único UPPER(email)            -> único (upper(email))
--   Bitmap                        -> btree (EPAS no tiene bitmap)
--   Funcional con CASE            -> índice parcial WHERE activo = 'S'
--   Descendente                   -> DESC
--   Sin INCLUDE en Oracle         -> INCLUDE (covering index)
--   Nested table / JSON           -> GIN (ventaja de PostgreSQL/EPAS)
-- =============================================================================
SET search_path TO ventas, public;

CREATE UNIQUE INDEX uq_clientes_email
  ON clientes (upper(email));

CREATE INDEX ix_clientes_segmento
  ON clientes (segmento);

CREATE INDEX ix_clientes_activo_segmento
  ON clientes (activo, segmento);

CREATE INDEX ix_clientes_nombre_mayus
  ON clientes (upper(nombre));

CREATE INDEX ix_clientes_telefono
  ON clientes (telefono);

-- Ventaja de EPAS: índice GIN sobre arreglo (equivalente funcional a la
-- nested table de Oracle para búsquedas por teléfono).
CREATE INDEX ix_clientes_telefonos_gin
  ON clientes USING gin (telefonos);

CREATE INDEX ix_direcciones_cliente
  ON direcciones_entrega (cliente_id);

CREATE INDEX ix_paises_region
  ON paises (region_id);

CREATE INDEX ix_categorias_padre
  ON categorias (categoria_padre_id);

CREATE INDEX ix_empleados_manager
  ON empleados (manager_id);

CREATE INDEX ix_productos_categoria_activo
  ON productos (categoria_id, activo);

-- Equivalente al índice funcional con CASE de Oracle.
CREATE INDEX ix_productos_activos_precio
  ON productos (precio)
  WHERE activo = 'S';

-- Ventaja de EPAS: consultas por claves/valores JSONB.
CREATE INDEX ix_productos_atributos_gin
  ON productos USING gin (atributos jsonb_path_ops);

CREATE INDEX ix_pedidos_cliente_fecha
  ON pedidos (cliente_id, fecha_pedido DESC);

CREATE INDEX ix_pedidos_estado
  ON pedidos (estado);

CREATE INDEX ix_pedidos_fecha
  ON pedidos (fecha_pedido);

CREATE INDEX ix_pedidos_empleado
  ON pedidos (empleado_id);

-- Covering index: evita ir a la tabla en reportes por estado.
CREATE INDEX ix_pedidos_estado_include
  ON pedidos (estado) INCLUDE (cliente_id, total);

-- El bitmap de Oracle (bix_pedidos_moneda) se reemplaza por btree.
CREATE INDEX ix_pedidos_moneda
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

COMMENT ON INDEX ix_productos_activos_precio IS
  'Reemplazo del índice funcional CASE de Oracle (índice parcial)';
COMMENT ON INDEX ix_pedidos_moneda IS
  'Reemplazo del bitmap bix_pedidos_moneda; EPAS no soporta bitmap';

ANALYZE;
