-- =============================================================================
-- 08_triggers.sql  |  Triggers EPAS con sintaxis Oracle
--
-- EPAS permite escribir triggers con :NEW/:OLD, BEFORE/AFTER y FOR EACH ROW.
-- Se recrean con DROP IF EXISTS porque el esquema se reinicia con frecuencia.
--
-- Los triggers se crean DESPUÉS de la carga de datos para evitar que la
-- auditoría se duplique durante la migración.
-- =============================================================================
SET search_path TO ventas, public;

-- ---------------------------------------------------------------------------
-- CLIENTES
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_clientes_bi ON clientes;
CREATE TRIGGER trg_clientes_bi
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
  IF :NEW.cliente_id IS NULL THEN
    :NEW.cliente_id := nextval('seq_clientes');
  END IF;
  :NEW.fecha_alta     := COALESCE(:NEW.fecha_alta, CURRENT_DATE);
  :NEW.creado_en      := COALESCE(:NEW.creado_en, CURRENT_TIMESTAMP);
  :NEW.actualizado_en := CURRENT_TIMESTAMP;
END;

DROP TRIGGER IF EXISTS trg_clientes_aud ON clientes;
CREATE TRIGGER trg_clientes_aud
AFTER INSERT OR UPDATE OR DELETE ON clientes
FOR EACH ROW
DECLARE
  v_pk      VARCHAR2(100);
  v_antes   TEXT;
  v_despues TEXT;
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

-- ---------------------------------------------------------------------------
-- DIRECCIONES
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_direcciones_bi ON direcciones_entrega;
CREATE TRIGGER trg_direcciones_bi
BEFORE INSERT ON direcciones_entrega
FOR EACH ROW
BEGIN
  IF :NEW.direccion_id IS NULL THEN
    :NEW.direccion_id := nextval('seq_direcciones');
  END IF;
END;

-- ---------------------------------------------------------------------------
-- PRODUCTOS
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_productos_precio ON productos;
CREATE TRIGGER trg_productos_precio
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
  IF :OLD.precio <> :NEW.precio THEN
    INSERT INTO precios_historial
      (historial_id, producto_id, precio_anterior, precio_nuevo, fecha, usuario)
    VALUES
      (nextval('seq_historial'), :NEW.producto_id, :OLD.precio, :NEW.precio,
       CURRENT_TIMESTAMP, UPPER(CURRENT_USER));

    pkg_auditoria.registrar(
      'PRODUCTOS', 'U', TO_CHAR(:NEW.producto_id),
      'precio=' || TO_CHAR(:OLD.precio),
      'precio=' || TO_CHAR(:NEW.precio),
      'TRIGGER');
  END IF;
END;

-- ---------------------------------------------------------------------------
-- PEDIDOS
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pedidos_bi ON pedidos;
CREATE TRIGGER trg_pedidos_bi
BEFORE INSERT OR UPDATE ON pedidos
FOR EACH ROW
DECLARE
  v_activo clientes.activo%TYPE;
BEGIN
  IF INSERTING AND :NEW.pedido_id IS NULL THEN
    :NEW.pedido_id := nextval('seq_pedidos');
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

-- ---------------------------------------------------------------------------
-- DETALLE
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pedido_detalle_biu ON pedido_detalle;
CREATE TRIGGER trg_pedido_detalle_biu
BEFORE INSERT OR UPDATE ON pedido_detalle
FOR EACH ROW
BEGIN
  :NEW.total_linea := ROUND(
    :NEW.cantidad * :NEW.precio_unitario *
    (1 - COALESCE(:NEW.descuento_pct, 0) / 100), 2);
END;

-- ---------------------------------------------------------------------------
-- PAGOS
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pagos_bi ON pagos;
CREATE TRIGGER trg_pagos_bi
BEFORE INSERT ON pagos
FOR EACH ROW
BEGIN
  IF :NEW.pago_id IS NULL THEN
    :NEW.pago_id := nextval('seq_pagos');
  END IF;
  IF :NEW.fecha_pago IS NULL THEN
    :NEW.fecha_pago := CURRENT_TIMESTAMP;
  END IF;
END;
