-- =============================================================================
-- 06_packages.sql  |  Paquetes EPAS migrados
--
-- Se conserva la API pública de Oracle para reducir cambios en la aplicación:
--   pkg_util, pkg_auditoria, pkg_ventas, pkg_mantenimiento.
--
-- Cambios obligados:
--   SYS_REFCURSOR      -> REFCURSOR
--   seq.NEXTVAL        -> nextval('seq')
--   DBMS_MVIEW.REFRESH -> REFRESH MATERIALIZED VIEW
--   EMPTY_CLOB()       -> ''
--   USER               -> UPPER(CURRENT_USER)
--
-- Ejecutar con edb-psql (no con psql genérico): el parser de EPAS entiende
-- los bloques CREATE PACKAGE sin separadores "/" de SQL*Plus.
-- =============================================================================
SET search_path TO ventas, public;

-- ---------------------------------------------------------------------------
-- PKG_UTIL
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_util AS
  c_iva CONSTANT NUMBER := 0.16;

  FUNCTION formatear_moneda(p_monto  IN NUMBER,
                            p_moneda IN VARCHAR2 DEFAULT 'MXN') RETURN VARCHAR2;

  FUNCTION es_dia_habil(p_fecha IN TIMESTAMP) RETURN CHAR;

  FUNCTION edad(p_fecha_nac IN TIMESTAMP,
                p_ref       IN TIMESTAMP DEFAULT CURRENT_TIMESTAMP) RETURN NUMBER;

  PROCEDURE log(p_mensaje IN VARCHAR2);
END pkg_util;

CREATE OR REPLACE PACKAGE BODY pkg_util AS
  FUNCTION formatear_moneda(p_monto  IN NUMBER,
                            p_moneda IN VARCHAR2 DEFAULT 'MXN') RETURN VARCHAR2 IS
  BEGIN
    RETURN p_moneda || ' ' || TO_CHAR(p_monto, 'FM999,999,990.00');
  END formatear_moneda;

  -- 2024-01-01 fue lunes; no depende de NLS ni del locale.
  FUNCTION es_dia_habil(p_fecha IN TIMESTAMP) RETURN CHAR IS
    v_dia NUMBER;
  BEGIN
    v_dia := MOD(MOD(CAST(p_fecha AS DATE) - DATE '2024-01-01', 7) + 7, 7);
    RETURN CASE WHEN v_dia IN (5, 6) THEN 'N' ELSE 'S' END;
  END es_dia_habil;

  FUNCTION edad(p_fecha_nac IN TIMESTAMP,
                p_ref       IN TIMESTAMP DEFAULT CURRENT_TIMESTAMP) RETURN NUMBER IS
  BEGIN
    IF p_fecha_nac IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN FLOOR(MONTHS_BETWEEN(p_ref, p_fecha_nac) / 12);
  END edad;

  PROCEDURE log(p_mensaje IN VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('[VENTAS] ' || p_mensaje);
  END log;
END pkg_util;

-- ---------------------------------------------------------------------------
-- PKG_AUDITORIA
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_auditoria AS
  PROCEDURE registrar(p_tabla     IN VARCHAR2,
                      p_operacion IN CHAR,
                      p_pk        IN VARCHAR2,
                      p_antes     IN TEXT,
                      p_despues   IN TEXT,
                      p_origen    IN VARCHAR2 DEFAULT 'TRIGGER');

  FUNCTION usuario_actual RETURN VARCHAR2;
END pkg_auditoria;

CREATE OR REPLACE PACKAGE BODY pkg_auditoria AS
  PROCEDURE registrar(p_tabla     IN VARCHAR2,
                      p_operacion IN CHAR,
                      p_pk        IN VARCHAR2,
                      p_antes     IN TEXT,
                      p_despues   IN TEXT,
                      p_origen    IN VARCHAR2 DEFAULT 'TRIGGER') IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO auditoria_cambios
      (tabla, operacion, pk_valor, usuario, datos_antes, datos_despues, origen)
    VALUES
      (p_tabla, p_operacion, p_pk, usuario_actual(), p_antes, p_despues, p_origen);
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('Aviso auditoría: ' || SQLERRM);
  END registrar;

  FUNCTION usuario_actual RETURN VARCHAR2 IS
  BEGIN
    RETURN UPPER(CURRENT_USER);
  END usuario_actual;
END pkg_auditoria;

-- ---------------------------------------------------------------------------
-- PKG_VENTAS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_ventas AS
  c_iva CONSTANT NUMBER := 0.16;

  PROCEDURE crear_pedido(p_cliente_id  IN NUMBER,
                         p_producto_id IN NUMBER,
                         p_cantidad    IN NUMBER,
                         p_pedido_id   OUT NUMBER);

  PROCEDURE agregar_detalle(p_pedido_id   IN NUMBER,
                            p_producto_id IN NUMBER,
                            p_cantidad    IN NUMBER);

  PROCEDURE recalcular_totales(p_pedido_id IN NUMBER);

  PROCEDURE confirmar_pedido(p_pedido_id IN NUMBER);

  PROCEDURE cancelar_pedido(p_pedido_id IN NUMBER,
                            p_motivo    IN VARCHAR2 DEFAULT NULL);

  FUNCTION total_pedido(p_pedido_id IN NUMBER) RETURN NUMBER;

  FUNCTION descuento_cliente(p_cliente_id IN NUMBER,
                             p_monto      IN NUMBER) RETURN NUMBER;

  FUNCTION estado_pedido(p_pedido_id IN NUMBER) RETURN VARCHAR2;

  PROCEDURE listar_pedidos(p_cliente_id IN NUMBER,
                           p_cursor     OUT REFCURSOR);

  PROCEDURE upsert_cliente(p_cliente_id IN NUMBER,
                           p_nombre     IN VARCHAR2,
                           p_email      IN VARCHAR2);

  PROCEDURE aplicar_descuento_masivo(p_porcentaje IN NUMBER);
END pkg_ventas;

CREATE OR REPLACE PACKAGE BODY pkg_ventas AS
  FUNCTION total_pedido(p_pedido_id IN NUMBER) RETURN NUMBER IS
    v_total NUMBER;
  BEGIN
    SELECT COALESCE(SUM(total_linea), 0)
      INTO v_total
      FROM pedido_detalle
     WHERE pedido_id = p_pedido_id;
    RETURN v_total;
  END total_pedido;

  FUNCTION descuento_cliente(p_cliente_id IN NUMBER,
                             p_monto      IN NUMBER) RETURN NUMBER IS
    v_segmento clientes.segmento%TYPE;
    v_pct      NUMBER;
  BEGIN
    SELECT segmento
      INTO v_segmento
      FROM clientes
     WHERE cliente_id = p_cliente_id;

    v_pct := CASE v_segmento
               WHEN 'A' THEN CASE WHEN p_monto >= 5000 THEN 0.08 ELSE 0.05 END
               WHEN 'B' THEN 0.03
               ELSE 0
             END;

    RETURN ROUND(COALESCE(p_monto, 0) * v_pct, 2);
  END descuento_cliente;

  FUNCTION estado_pedido(p_pedido_id IN NUMBER) RETURN VARCHAR2 IS
    v_estado pedidos.estado%TYPE;
  BEGIN
    SELECT estado INTO v_estado FROM pedidos WHERE pedido_id = p_pedido_id;
    RETURN v_estado;
  END estado_pedido;

  PROCEDURE recalcular_totales(p_pedido_id IN NUMBER) IS
    v_cliente_id pedidos.cliente_id%TYPE;
    v_subtotal   pedidos.subtotal%TYPE;
    v_descuento  pedidos.descuento%TYPE;
    v_impuesto   pedidos.impuesto%TYPE;
  BEGIN
    SELECT cliente_id INTO v_cliente_id FROM pedidos WHERE pedido_id = p_pedido_id;

    v_subtotal  := total_pedido(p_pedido_id);
    v_descuento := descuento_cliente(v_cliente_id, v_subtotal);
    v_impuesto  := ROUND((v_subtotal - v_descuento) * c_iva, 2);

    UPDATE pedidos
       SET subtotal  = v_subtotal,
           descuento = v_descuento,
           impuesto  = v_impuesto,
           total     = v_subtotal - v_descuento + v_impuesto,
           version   = version + 1
     WHERE pedido_id = p_pedido_id;
  END recalcular_totales;

  PROCEDURE agregar_detalle(p_pedido_id   IN NUMBER,
                            p_producto_id IN NUMBER,
                            p_cantidad    IN NUMBER) IS
    v_precio productos.precio%TYPE;
  BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
      RAISE_APPLICATION_ERROR(-20020, 'La cantidad debe ser mayor que cero');
    END IF;

    SELECT precio
      INTO v_precio
      FROM productos
     WHERE producto_id = p_producto_id
       AND activo = 'S';

    INSERT INTO pedido_detalle
      (pedido_id, producto_id, cantidad, precio_unitario, descuento_pct)
    VALUES
      (p_pedido_id, p_producto_id, p_cantidad, v_precio, 0);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20021, 'Producto inexistente o inactivo');
  END agregar_detalle;

  PROCEDURE crear_pedido(p_cliente_id  IN NUMBER,
                         p_producto_id IN NUMBER,
                         p_cantidad    IN NUMBER,
                         p_pedido_id   OUT NUMBER) IS
    v_activo clientes.activo%TYPE;
  BEGIN
    SELECT activo INTO v_activo FROM clientes WHERE cliente_id = p_cliente_id;
    IF v_activo <> 'S' THEN
      RAISE_APPLICATION_ERROR(-20010, 'El cliente está inactivo');
    END IF;

    p_pedido_id := nextval('seq_pedidos');

    INSERT INTO pedidos
      (pedido_id, cliente_id, fecha_pedido, estado, moneda, creado_por)
    VALUES
      (p_pedido_id, p_cliente_id, LOCALTIMESTAMP, 'NUEVO', 'MXN',
       UPPER(CURRENT_USER));

    agregar_detalle(p_pedido_id, p_producto_id, p_cantidad);
    recalcular_totales(p_pedido_id);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20011, 'Cliente o producto no encontrado');
  END crear_pedido;

  PROCEDURE confirmar_pedido(p_pedido_id IN NUMBER) IS
    v_estado pedidos.estado%TYPE;
  BEGIN
    SELECT estado INTO v_estado
      FROM pedidos
     WHERE pedido_id = p_pedido_id
       FOR UPDATE;

    IF v_estado <> 'NUEVO' THEN
      RAISE_APPLICATION_ERROR(-20030,
        'Solo se confirma un pedido NUEVO; estado actual: ' || v_estado);
    END IF;

    UPDATE pedidos SET estado = 'CONFIRMADO', version = version + 1
     WHERE pedido_id = p_pedido_id;

    pkg_auditoria.registrar('PEDIDOS', 'U', TO_CHAR(p_pedido_id),
                            'estado=' || v_estado, 'estado=CONFIRMADO', 'PACKAGE');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20031, 'Pedido inexistente');
  END confirmar_pedido;

  PROCEDURE cancelar_pedido(p_pedido_id IN NUMBER,
                            p_motivo    IN VARCHAR2 DEFAULT NULL) IS
    v_estado pedidos.estado%TYPE;
    v_notas  pedidos.notas%TYPE;
  BEGIN
    SELECT estado, notas
      INTO v_estado, v_notas
      FROM pedidos
     WHERE pedido_id = p_pedido_id
       FOR UPDATE;

    IF v_estado IN ('ENTREGADO', 'CANCELADO') THEN
      RAISE_APPLICATION_ERROR(-20032,
        'No se puede cancelar un pedido en estado ' || v_estado);
    END IF;

    UPDATE pedidos
       SET estado = 'CANCELADO',
           notas  = SUBSTR(COALESCE(v_notas, '') || CHR(10) ||
                           'Cancelado: ' || COALESCE(p_motivo, 'sin motivo'), 1, 4000),
           version = version + 1
     WHERE pedido_id = p_pedido_id;

    pkg_auditoria.registrar('PEDIDOS', 'U', TO_CHAR(p_pedido_id),
                            'estado=' || v_estado, 'estado=CANCELADO', 'PACKAGE');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20033, 'Pedido inexistente');
  END cancelar_pedido;

  PROCEDURE listar_pedidos(p_cliente_id IN NUMBER,
                           p_cursor     OUT REFCURSOR) IS
  BEGIN
    OPEN p_cursor FOR
      SELECT p.pedido_id,
             p.fecha_pedido,
             p.estado,
             p.total,
             COUNT(d.detalle_id) AS lineas
        FROM pedidos p
        LEFT JOIN pedido_detalle d ON d.pedido_id = p.pedido_id
       WHERE p.cliente_id = p_cliente_id
       GROUP BY p.pedido_id, p.fecha_pedido, p.estado, p.total
       ORDER BY p.fecha_pedido DESC;
  END listar_pedidos;

  PROCEDURE upsert_cliente(p_cliente_id IN NUMBER,
                           p_nombre     IN VARCHAR2,
                           p_email      IN VARCHAR2) IS
  BEGIN
    MERGE INTO clientes c
    USING (SELECT p_cliente_id AS id FROM dual) s
       ON (c.cliente_id = s.id)
    WHEN MATCHED THEN
      UPDATE SET nombre = p_nombre,
                 email = p_email,
                 actualizado_en = LOCALTIMESTAMP
    WHEN NOT MATCHED THEN
      INSERT (cliente_id, codigo, nombre, email, fecha_alta, segmento, activo)
      VALUES (p_cliente_id, 'CLI-' || LPAD(p_cliente_id, 5, '0'),
              p_nombre, p_email, CURRENT_DATE, 'C', 'S');
  END upsert_cliente;

  PROCEDURE aplicar_descuento_masivo(p_porcentaje IN NUMBER) IS
  BEGIN
    IF p_porcentaje IS NULL OR p_porcentaje < 0 OR p_porcentaje > 50 THEN
      RAISE_APPLICATION_ERROR(-20040, 'El porcentaje debe estar entre 0 y 50');
    END IF;

    UPDATE productos
       SET precio = ROUND(precio * (1 - p_porcentaje / 100), 2)
     WHERE activo = 'S';

    pkg_util.log('Descuento masivo aplicado: ' || p_porcentaje || '%');
  END aplicar_descuento_masivo;
END pkg_ventas;

-- ---------------------------------------------------------------------------
-- PKG_MANTENIMIENTO
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_mantenimiento AS
  PROCEDURE refrescar_mv(p_nombre IN VARCHAR2);
  PROCEDURE analizar_tabla(p_tabla IN VARCHAR2);
  FUNCTION contar(p_tabla IN VARCHAR2) RETURN NUMBER;
END pkg_mantenimiento;

CREATE OR REPLACE PACKAGE BODY pkg_mantenimiento AS
  PROCEDURE refrescar_mv(p_nombre IN VARCHAR2) IS
  BEGIN
    IF NOT (p_nombre ~ '^[a-z_][a-z0-9_]*$') THEN
      RAISE_APPLICATION_ERROR(-20050, 'Nombre de MV inválido');
    END IF;
    EXECUTE IMMEDIATE 'REFRESH MATERIALIZED VIEW ' || p_nombre;
  END refrescar_mv;

  PROCEDURE analizar_tabla(p_tabla IN VARCHAR2) IS
  BEGIN
    IF NOT (p_tabla ~ '^[a-z_][a-z0-9_]*$') THEN
      RAISE_APPLICATION_ERROR(-20051, 'Nombre de tabla inválido');
    END IF;
    EXECUTE IMMEDIATE 'ANALYZE ' || quote_ident(p_tabla);
  END analizar_tabla;

  FUNCTION contar(p_tabla IN VARCHAR2) RETURN NUMBER IS
    v_count NUMBER;
  BEGIN
    IF NOT (p_tabla ~ '^[a-z_][a-z0-9_]*$') THEN
      RAISE_APPLICATION_ERROR(-20052, 'Nombre de tabla inválido');
    END IF;
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || quote_ident(p_tabla)
      INTO v_count;
    RETURN v_count;
  END contar;
END pkg_mantenimiento;
