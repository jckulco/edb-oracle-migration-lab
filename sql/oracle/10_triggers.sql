-- =============================================================================
-- 10_triggers.sql  |  Triggers Oracle
--
-- Patrones incluidos:
--   * Asignación de secuencia / identidad en BEFORE INSERT.
--   * Validación de reglas de negocio.
--   * Cálculo de columnas derivadas (total_linea).
--   * Auditoría con PRAGMA AUTONOMOUS_TRANSACTION desde un paquete.
--   * Historial de precios disparado por UPDATE OF.
--
-- En EPAS se recrean con sintaxis Oracle compatible; revisa 08_triggers.sql.
-- =============================================================================
SET DEFINE OFF

-- ---------------------------------------------------------------------------
-- CLIENTES
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_clientes_bi
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
  IF :NEW.cliente_id IS NULL THEN
    :NEW.cliente_id := seq_clientes.NEXTVAL;
  END IF;
  :NEW.fecha_alta     := NVL(:NEW.fecha_alta, TRUNC(SYSDATE));
  :NEW.creado_en      := NVL(:NEW.creado_en, SYSTIMESTAMP);
  :NEW.actualizado_en := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER trg_clientes_aud
AFTER INSERT OR UPDATE OR DELETE ON clientes
FOR EACH ROW
DECLARE
  v_pk      VARCHAR2(100);
  v_antes   CLOB;
  v_despues CLOB;
BEGIN
  IF INSERTING THEN
    v_pk := TO_CHAR(:NEW.cliente_id);
    v_despues := 'nombre=' || :NEW.nombre ||
                 ';segmento=' || :NEW.segmento ||
                 ';limite=' || TO_CHAR(:NEW.limite_credito) ||
                 ';saldo=' || TO_CHAR(:NEW.saldo) ||
                 ';activo=' || :NEW.activo;
    pkg_auditoria.registrar('CLIENTES', 'I', v_pk, NULL, v_despues, 'TRIGGER');

  ELSIF UPDATING THEN
    v_pk := TO_CHAR(:NEW.cliente_id);
    v_antes := 'nombre=' || :OLD.nombre ||
               ';segmento=' || :OLD.segmento ||
               ';limite=' || TO_CHAR(:OLD.limite_credito) ||
               ';saldo=' || TO_CHAR(:OLD.saldo) ||
               ';activo=' || :OLD.activo;
    v_despues := 'nombre=' || :NEW.nombre ||
                 ';segmento=' || :NEW.segmento ||
                 ';limite=' || TO_CHAR(:NEW.limite_credito) ||
                 ';saldo=' || TO_CHAR(:NEW.saldo) ||
                 ';activo=' || :NEW.activo;
    pkg_auditoria.registrar('CLIENTES', 'U', v_pk, v_antes, v_despues, 'TRIGGER');

  ELSE
    v_pk := TO_CHAR(:OLD.cliente_id);
    v_antes := 'nombre=' || :OLD.nombre ||
               ';segmento=' || :OLD.segmento ||
               ';limite=' || TO_CHAR(:OLD.limite_credito) ||
               ';saldo=' || TO_CHAR(:OLD.saldo) ||
               ';activo=' || :OLD.activo;
    pkg_auditoria.registrar('CLIENTES', 'D', v_pk, v_antes, NULL, 'TRIGGER');
  END IF;
END;
/

-- ---------------------------------------------------------------------------
-- DIRECCIONES
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_direcciones_bi
BEFORE INSERT ON direcciones_entrega
FOR EACH ROW
BEGIN
  IF :NEW.direccion_id IS NULL THEN
    :NEW.direccion_id := seq_direcciones.NEXTVAL;
  END IF;
END;
/

-- ---------------------------------------------------------------------------
-- PRODUCTOS: historial de precios + auditoría
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_productos_precio
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
  IF :OLD.precio <> :NEW.precio THEN
    INSERT INTO precios_historial
      (historial_id, producto_id, precio_anterior, precio_nuevo, fecha, usuario)
    VALUES
      (seq_historial.NEXTVAL, :NEW.producto_id, :OLD.precio, :NEW.precio,
       SYSTIMESTAMP, UPPER(CURRENT_USER));

    pkg_auditoria.registrar(
      'PRODUCTOS', 'U', TO_CHAR(:NEW.producto_id),
      'precio=' || TO_CHAR(:OLD.precio),
      'precio=' || TO_CHAR(:NEW.precio),
      'TRIGGER');
  END IF;
END;
/

-- ---------------------------------------------------------------------------
-- PEDIDOS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_pedidos_bi
BEFORE INSERT OR UPDATE ON pedidos
FOR EACH ROW
DECLARE
  v_activo clientes.activo%TYPE;
BEGIN
  IF INSERTING AND :NEW.pedido_id IS NULL THEN
    :NEW.pedido_id := seq_pedidos.NEXTVAL;
  END IF;

  BEGIN
    SELECT activo INTO v_activo
      FROM clientes
     WHERE cliente_id = :NEW.cliente_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20013, 'El cliente no existe');
  END;

  IF v_activo <> 'S' THEN
    RAISE_APPLICATION_ERROR(-20010, 'El cliente está inactivo');
  END IF;

  IF :NEW.estado IS NULL THEN
    :NEW.estado := 'NUEVO';
  END IF;

  IF :NEW.total < 0 THEN
    RAISE_APPLICATION_ERROR(-20012, 'El total no puede ser negativo');
  END IF;
END;
/

-- ---------------------------------------------------------------------------
-- DETALLE DE PEDIDO
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_pedido_detalle_biu
BEFORE INSERT OR UPDATE ON pedido_detalle
FOR EACH ROW
BEGIN
  :NEW.total_linea := ROUND(
    :NEW.cantidad * :NEW.precio_unitario *
    (1 - NVL(:NEW.descuento_pct, 0) / 100), 2);
END;
/

-- ---------------------------------------------------------------------------
-- PAGOS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_pagos_bi
BEFORE INSERT ON pagos
FOR EACH ROW
BEGIN
  IF :NEW.pago_id IS NULL THEN
    :NEW.pago_id := seq_pagos.NEXTVAL;
  END IF;
  IF :NEW.fecha_pago IS NULL THEN
    :NEW.fecha_pago := SYSTIMESTAMP;
  END IF;
END;
/

SHOW ERRORS
