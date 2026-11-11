-- =============================================================================
-- 03_constraints.sql  |  Claves foráneas después de la carga
--
-- Patrón recomendado para migraciones grandes:
--   1. Cargar datos sin FKs (más rápido y tolerante a orden).
--   2. Crear FKs como NOT VALID (toma solo un lock breve).
--   3. VALIDATE CONSTRAINT (valida sin bloquear escrituras).
--
-- Si la validación falla, el ETL o la limpieza de datos debe corregir las
-- filas huérfanas antes de reintentar.
-- =============================================================================
SET search_path TO ventas, public;

ALTER TABLE paises
  ADD CONSTRAINT fk_paises_region
  FOREIGN KEY (region_id) REFERENCES regiones (region_id) NOT VALID;

ALTER TABLE direcciones_entrega
  ADD CONSTRAINT fk_direcciones_cliente
  FOREIGN KEY (cliente_id) REFERENCES clientes (cliente_id)
  ON DELETE CASCADE NOT VALID;

ALTER TABLE categorias
  ADD CONSTRAINT fk_categorias_padre
  FOREIGN KEY (categoria_padre_id) REFERENCES categorias (categoria_id) NOT VALID;

ALTER TABLE productos
  ADD CONSTRAINT fk_productos_categoria
  FOREIGN KEY (categoria_id) REFERENCES categorias (categoria_id) NOT VALID;

ALTER TABLE empleados
  ADD CONSTRAINT fk_empleados_manager
  FOREIGN KEY (manager_id) REFERENCES empleados (empleado_id) NOT VALID;

ALTER TABLE pedidos
  ADD CONSTRAINT fk_pedidos_cliente
  FOREIGN KEY (cliente_id) REFERENCES clientes (cliente_id) NOT VALID;

ALTER TABLE pedidos
  ADD CONSTRAINT fk_pedidos_empleado
  FOREIGN KEY (empleado_id) REFERENCES empleados (empleado_id)
  DEFERRABLE INITIALLY DEFERRED NOT VALID;

ALTER TABLE pedido_detalle
  ADD CONSTRAINT fk_detalle_pedido
  FOREIGN KEY (pedido_id) REFERENCES pedidos (pedido_id)
  ON DELETE CASCADE NOT VALID;

ALTER TABLE pedido_detalle
  ADD CONSTRAINT fk_detalle_producto
  FOREIGN KEY (producto_id) REFERENCES productos (producto_id) NOT VALID;

ALTER TABLE pagos
  ADD CONSTRAINT fk_pagos_pedido
  FOREIGN KEY (pedido_id) REFERENCES pedidos (pedido_id) NOT VALID;

ALTER TABLE precios_historial
  ADD CONSTRAINT fk_historial_producto
  FOREIGN KEY (producto_id) REFERENCES productos (producto_id) NOT VALID;

-- Validación sin bloquear escrituras (toma ShareUpdateExclusiveLock).
ALTER TABLE paises            VALIDATE CONSTRAINT fk_paises_region;
ALTER TABLE direcciones_entrega VALIDATE CONSTRAINT fk_direcciones_cliente;
ALTER TABLE categorias        VALIDATE CONSTRAINT fk_categorias_padre;
ALTER TABLE productos         VALIDATE CONSTRAINT fk_productos_categoria;
ALTER TABLE empleados         VALIDATE CONSTRAINT fk_empleados_manager;
ALTER TABLE pedidos           VALIDATE CONSTRAINT fk_pedidos_cliente;
ALTER TABLE pedidos           VALIDATE CONSTRAINT fk_pedidos_empleado;
ALTER TABLE pedido_detalle    VALIDATE CONSTRAINT fk_detalle_pedido;
ALTER TABLE pedido_detalle    VALIDATE CONSTRAINT fk_detalle_producto;
ALTER TABLE pagos             VALIDATE CONSTRAINT fk_pagos_pedido;
ALTER TABLE precios_historial VALIDATE CONSTRAINT fk_historial_producto;

-- Reglas de negocio adicionales que en Oracle viven en 05_constraints.sql.
COMMENT ON CONSTRAINT fk_pedidos_empleado ON pedidos IS
  'Diferida: permite insertar pedido y detalle en la misma transacción';
