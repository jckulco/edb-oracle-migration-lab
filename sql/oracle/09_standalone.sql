-- =============================================================================
-- 09_standalone.sql  |  Función y procedimientos fuera de paquetes
--
-- No todo el código Oracle vive en paquetes. Las funciones y procedimientos
-- sueltos también se migran y se prueban desde Python.
-- =============================================================================
SET DEFINE OFF

CREATE OR REPLACE FUNCTION fn_calcular_impuesto(
  p_monto IN NUMBER,
  p_tasa  IN NUMBER DEFAULT 0.16
) RETURN NUMBER IS
BEGIN
  RETURN ROUND(NVL(p_monto, 0) * NVL(p_tasa, 0.16), 2);
END fn_calcular_impuesto;
/

CREATE OR REPLACE FUNCTION fn_promedio_ventas_cliente(
  p_cliente_id IN NUMBER
) RETURN NUMBER IS
  v_promedio NUMBER;
BEGIN
  SELECT NVL(AVG(total), 0)
    INTO v_promedio
    FROM pedidos
   WHERE cliente_id = p_cliente_id
     AND estado <> 'CANCELADO';

  RETURN ROUND(v_promedio, 2);
END fn_promedio_ventas_cliente;
/

CREATE OR REPLACE PROCEDURE sp_actualizar_saldos IS
  CURSOR c_clientes IS
    SELECT cliente_id FROM clientes WHERE activo = 'S';
  v_total NUMBER;
BEGIN
  FOR r IN c_clientes LOOP
    SELECT NVL(SUM(total), 0)
      INTO v_total
      FROM pedidos
     WHERE cliente_id = r.cliente_id
       AND estado <> 'CANCELADO';

    UPDATE clientes
       SET saldo = v_total,
           actualizado_en = LOCALTIMESTAMP
     WHERE cliente_id = r.cliente_id;
  END LOOP;

  pkg_util.log('Saldos actualizados para clientes activos');
END sp_actualizar_saldos;
/

SHOW ERRORS
