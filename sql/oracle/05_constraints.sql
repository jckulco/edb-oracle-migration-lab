-- =============================================================================
-- 05_constraints.sql  |  Ajustes de integridad y comentarios
--
-- Las restricciones principales se declaran en 02_tables.sql. Aquí se agrega
-- una restricción diferida adicional y se documenta el modelo para el
-- diccionario de datos.
-- =============================================================================
SET DEFINE OFF

-- Regla de negocio adicional: la versión de bloqueo optimista es positiva.
ALTER TABLE pedidos
  ADD CONSTRAINT ck_pedidos_version
  CHECK (version > 0);

-- Validación de montos a nivel de detalle (regla de negocio).
ALTER TABLE pedido_detalle
  ADD CONSTRAINT ck_detalle_total_positivo
  CHECK (total_linea >= 0);

COMMENT ON TABLE regiones IS 'Catálogo de regiones comerciales';
COMMENT ON TABLE paises IS 'Países asociados a una región';
COMMENT ON TABLE direcciones_entrega IS 'Direcciones de entrega por cliente';
COMMENT ON TABLE categorias IS 'Categorías jerárquicas de productos';
COMMENT ON TABLE productos IS 'Catálogo de productos con LOB, XML y JSON';
COMMENT ON TABLE empleados IS 'Empleados con jerarquía manager_id';
COMMENT ON TABLE pagos IS 'Pagos por pedido, con RAW(16) y JSON';
COMMENT ON COLUMN pedidos.tiempo_entrega IS 'INTERVAL DAY TO SECOND';
COMMENT ON COLUMN pagos.referencia IS 'RAW(16): identificador binario de la transacción';

SHOW ERRORS
