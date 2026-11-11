-- =============================================================================
-- 11_seed.sql  |  Datos deterministas del laboratorio
--
-- Genera un volumen pequeño pero suficiente para probar:
--   * 60 clientes (uno inactivo), 80 direcciones, 40 productos, 15 empleados.
--   * 300 pedidos, ~750 líneas, ~200 pagos.
--   * Auditoría e historial de precios producidos por triggers reales.
--
-- El script asume el esquema vacío (00_reset.sql) y se ejecuta como VENTAS.
-- Es determinista salvo por SYSTIMESTAMP/SYS_GUID, que el ETL copia tal cual.
-- =============================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
ALTER SESSION SET TIME_ZONE = 'UTC';
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

DECLARE
  v_fecha        TIMESTAMP(6);
  v_fecha_dia    DATE;
  v_estado       VARCHAR2(20);
  v_cliente      NUMBER(10);
  v_empleado     NUMBER(6);
  v_producto_id  NUMBER(10);
  v_precio       NUMBER(12,2);
  v_total        NUMBER(14,2);
  v_metodo       VARCHAR2(20);
  v_nombre       VARCHAR2(150);
  v_sku          VARCHAR2(30);
  v_color        VARCHAR2(20);
  v_talla        VARCHAR2(5);
  TYPE t_precios IS TABLE OF NUMBER(12,2) INDEX BY PLS_INTEGER;
  v_precios t_precios;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== Cargando datos del laboratorio ===');

  -- -----------------------------------------------------------------------
  -- Regiones y países
  -- -----------------------------------------------------------------------
  INSERT INTO regiones (region_id, nombre, codigo) VALUES (1, 'Norteamérica', 'NA');
  INSERT INTO regiones (region_id, nombre, codigo) VALUES (2, 'Latinoamérica', 'LA');
  INSERT INTO regiones (region_id, nombre, codigo) VALUES (3, 'Europa', 'EU');
  INSERT INTO regiones (region_id, nombre, codigo) VALUES (4, 'Asia-Pacífico', 'AP');

  INSERT INTO paises (pais_id, codigo, nombre, region_id)
    VALUES (1, 'MX', 'México', 1);
  INSERT INTO paises (pais_id, codigo, nombre, region_id)
    VALUES (2, 'US', 'Estados Unidos', 1);
  INSERT INTO paises (pais_id, codigo, nombre, region_id)
    VALUES (3, 'CA', 'Canadá', 1);
  INSERT INTO paises (pais_id, codigo, nombre, region_id)
    VALUES (4, 'CO', 'Colombia', 2);
  INSERT INTO paises (pais_id, codigo, nombre, region_id)
    VALUES (5, 'AR', 'Argentina', 2);
  INSERT INTO paises (pais_id, codigo, nombre, region_id)
    VALUES (6, 'ES', 'España', 3);
  INSERT INTO paises (pais_id, codigo, nombre, region_id)
    VALUES (7, 'DE', 'Alemania', 3);
  INSERT INTO paises (pais_id, codigo, nombre, region_id)
    VALUES (8, 'JP', 'Japón', 4);

  -- -----------------------------------------------------------------------
  -- Clientes (objeto T_DIRECCION y colección anidada T_TELEFONOS)
  -- -----------------------------------------------------------------------
  FOR i IN 1..60 LOOP
    INSERT INTO clientes
      (cliente_id, codigo, nombre, email, telefono, fecha_alta, fecha_nacimiento,
       segmento, limite_credito, saldo, activo, direccion, telefonos, notas,
       datos_extra, creado_en)
    VALUES
      (i,
       'CLI-' || LPAD(i, 5, '0'),
       'Cliente ' || LPAD(i, 2, '0'),
       'cliente' || LPAD(i, 2, '0') || '@example.com',
       '555' || LPAD(i, 7, '0'),
       DATE '2023-01-01' + MOD(i, 365),
       DATE '1980-01-01' + MOD(i * 37, 9000),
       CASE MOD(i, 3) WHEN 0 THEN 'A' WHEN 1 THEN 'B' ELSE 'C' END,
       CASE MOD(i, 3) WHEN 0 THEN 50000 WHEN 1 THEN 25000 ELSE 10000 END,
       0,
       CASE WHEN i = 60 THEN 'N' ELSE 'S' END,
       t_direccion('Calle ' || i || ' #' || (100 + i),
                   'Ciudad ' || MOD(i, 10),
                   'Estado ' || MOD(i, 5),
                   'MX',
                   LPAD(i, 5, '0')),
       t_telefonos('555' || LPAD(i, 7, '0'), '777' || LPAD(i, 7, '0')),
       'Cliente de laboratorio ' || i,
       '{"canal":"' || CASE MOD(i, 4) WHEN 0 THEN 'web' WHEN 1 THEN 'tienda'
                                      WHEN 2 THEN 'telefono' ELSE 'partner' END ||
       '","score":' || MOD(i * 13, 100) || ',"vip":' ||
       CASE WHEN MOD(i, 3) = 0 THEN 'true' ELSE 'false' END || '}',
       TIMESTAMP '2024-01-01 00:00:00' + NUMTODSINTERVAL(i, 'MINUTE'));
  END LOOP;

  -- Direcciones de entrega: una principal por cliente y 20 sucursales.
  FOR i IN 1..80 LOOP
    v_cliente := MOD(i - 1, 60) + 1;
    INSERT INTO direcciones_entrega
      (direccion_id, cliente_id, etiqueta, calle, ciudad, estado, pais,
       codigo_postal, es_principal)
    VALUES
      (i, v_cliente,
       CASE WHEN i <= 60 THEN 'PRINCIPAL' ELSE 'SUCURSAL' END,
       'Av. Entrega ' || i,
       'Ciudad ' || MOD(i, 10),
       'Estado ' || MOD(i, 5),
       'MX',
       LPAD(1000 + i, 5, '0'),
       CASE WHEN i <= 60 THEN 'S' ELSE 'N' END);
  END LOOP;

  -- -----------------------------------------------------------------------
  -- Categorías (5 raíces, 7 hijas)
  -- -----------------------------------------------------------------------
  INSERT INTO categorias (categoria_id, nombre, categoria_padre_id, activo)
    VALUES (1, 'Electrónica', NULL, 'S');
  INSERT INTO categorias (categoria_id, nombre, categoria_padre_id, activo)
    VALUES (2, 'Hogar', NULL, 'S');
  INSERT INTO categorias (categoria_id, nombre, categoria_padre_id, activo)
    VALUES (3, 'Deportes', NULL, 'S');
  INSERT INTO categorias (categoria_id, nombre, categoria_padre_id, activo)
    VALUES (4, 'Oficina', NULL, 'S');
  INSERT INTO categorias (categoria_id, nombre, categoria_padre_id, activo)
    VALUES (5, 'Juguetes', NULL, 'S');

  FOR i IN 6..12 LOOP
    INSERT INTO categorias (categoria_id, nombre, categoria_padre_id, activo)
    VALUES (i, 'Subcategoría ' || i, MOD(i - 6, 5) + 1, 'S');
  END LOOP;

  -- -----------------------------------------------------------------------
  -- Productos (identidad nativa, XMLTYPE, BLOB, JSON en CLOB)
  -- -----------------------------------------------------------------------
  FOR i IN 1..40 LOOP
    v_sku    := 'PROD-' || LPAD(i, 4, '0');
    v_nombre := 'Producto ' || LPAD(i, 2, '0');
    v_color  := CASE MOD(i, 4) WHEN 0 THEN 'rojo' WHEN 1 THEN 'azul'
                               WHEN 2 THEN 'negro' ELSE 'blanco' END;
    v_talla  := CASE MOD(i, 3) WHEN 0 THEN 'S' WHEN 1 THEN 'M' ELSE 'L' END;
    v_precio := ROUND(80 + i * 17.35, 2);

    INSERT INTO productos
      (sku, nombre, descripcion, categoria_id, precio, costo, calificacion,
       peso_kg, garantia_meses, activo, imagen, ficha_xml, atributos,
       fecha_creacion)
    VALUES
      (v_sku, v_nombre,
       'Descripción del producto ' || i || ' para el laboratorio.',
       MOD(i - 1, 12) + 1,
       v_precio,
       ROUND(v_precio * 0.62, 2),
       CAST(3 + MOD(i, 20) / 10 AS BINARY_FLOAT),
       ROUND(0.2 + MOD(i * 7, 50) / 10, 3),
       CASE MOD(i, 4) WHEN 0 THEN 12 WHEN 1 THEN 6 WHEN 2 THEN 24 ELSE 0 END,
       CASE WHEN MOD(i, 11) = 0 THEN 'N' ELSE 'S' END,
       HEXTORAW('89504E470D0A1A0A'),
       XMLTYPE('<producto><sku>' || v_sku || '</sku><nombre>' || v_nombre ||
               '</nombre><precio>' || v_precio || '</precio></producto>'),
       '{"color":"' || v_color || '","talla":"' || v_talla ||
       '","importado":' || CASE WHEN MOD(i, 2) = 0 THEN 'true' ELSE 'false' END || '}',
       TIMESTAMP '2024-01-01 00:00:00 +00:00')
    RETURNING producto_id INTO v_producto_id;

    v_precios(v_producto_id) := v_precio;
  END LOOP;

  -- -----------------------------------------------------------------------
  -- Empleados: jerarquía de 3 niveles
  -- -----------------------------------------------------------------------
  FOR i IN 1..15 LOOP
    INSERT INTO empleados
      (empleado_id, nombre, email, manager_id, fecha_ingreso, salario,
       comision, activo)
    VALUES
      (i,
       'Empleado ' || LPAD(i, 2, '0'),
       'empleado' || LPAD(i, 2, '0') || '@example.com',
       CASE
         WHEN i = 1 THEN NULL
         WHEN i <= 3 THEN 1
         ELSE 2 + MOD(i, 2)
       END,
       DATE '2015-01-01' + i * 30,
       8000 + i * 750,
       CASE WHEN i <= 3 THEN 0 ELSE MOD(i, 5) END,
       CASE WHEN MOD(i, 19) = 0 THEN 'N' ELSE 'S' END);
  END LOOP;

  -- -----------------------------------------------------------------------
  -- Pedidos, detalle y pagos
  -- -----------------------------------------------------------------------
  FOR i IN 1..300 LOOP
    v_cliente  := MOD(i - 1, 59) + 1;         -- el cliente 60 está inactivo
    v_empleado := MOD(i - 1, 15) + 1;
    v_fecha    := TIMESTAMP '2024-01-01 08:00:00'
                  + NUMTODSINTERVAL(i * 36, 'HOUR');
    v_fecha_dia := CAST(v_fecha AS DATE);
    v_estado   := CASE MOD(i, 10)
                    WHEN 0 THEN 'CANCELADO'
                    WHEN 1 THEN 'NUEVO'
                    WHEN 2 THEN 'CONFIRMADO'
                    WHEN 3 THEN 'ENVIADO'
                    ELSE 'ENTREGADO'
                  END;

    INSERT INTO pedidos
      (pedido_id, cliente_id, empleado_id, fecha_pedido,
       fecha_entrega_estimada, fecha_entrega_real, estado, moneda, notas,
       creado_por, tiempo_entrega)
    VALUES
      (i, v_cliente, v_empleado, v_fecha,
       v_fecha_dia + 7,
       CASE WHEN v_estado = 'ENTREGADO'
            THEN FROM_TZ(v_fecha, 'UTC') + NUMTODSINTERVAL(5, 'DAY')
            ELSE NULL END,
       v_estado,
       CASE WHEN MOD(i, 7) = 0 THEN 'USD' ELSE 'MXN' END,
       CASE WHEN MOD(i, 5) = 0 THEN 'Entrega en horario vespertino' ELSE NULL END,
       UPPER(CURRENT_USER),
       NUMTODSINTERVAL(MOD(i, 72) + 1, 'HOUR'));

    FOR j IN 0..MOD(i, 3) LOOP
      v_producto_id := MOD(i * 3 + j * 7, 40) + 1;
      INSERT INTO pedido_detalle
        (pedido_id, producto_id, cantidad, precio_unitario, descuento_pct)
      VALUES
        (i, v_producto_id, 1 + MOD(i + j, 4), v_precios(v_producto_id),
         CASE MOD(i + j, 5) WHEN 0 THEN 5 WHEN 1 THEN 10 ELSE 0 END);
    END LOOP;

    pkg_ventas.recalcular_totales(i);
  END LOOP;

  FOR i IN 1..300 LOOP
    SELECT estado, total, fecha_pedido
      INTO v_estado, v_total, v_fecha
      FROM pedidos
     WHERE pedido_id = i;

    IF v_estado NOT IN ('NUEVO', 'CANCELADO') THEN
      v_metodo := CASE MOD(i, 4)
                    WHEN 0 THEN 'TARJETA'
                    WHEN 1 THEN 'TRANSFERENCIA'
                    WHEN 2 THEN 'EFECTIVO'
                    ELSE 'PAYPAL'
                  END;

      INSERT INTO pagos
        (pago_id, pedido_id, fecha_pago, metodo, monto, referencia, confirmado,
         datos_respuesta)
      VALUES
        (i, i, FROM_TZ(v_fecha, 'UTC') + NUMTODSINTERVAL(2, 'HOUR'),
         v_metodo, v_total, SYS_GUID(), 'S',
         '{"autorizacion":"AUTH-' || i || '","aprobado":true}');
    END IF;
  END LOOP;

  -- Actualización de precios: dispara historial y auditoría.
  FOR i IN 5..40 LOOP
    IF MOD(i, 5) = 0 THEN
      UPDATE productos SET precio = ROUND(precio * 1.07, 2)
       WHERE producto_id = i;
    END IF;
  END LOOP;

  sp_actualizar_saldos;
  COMMIT;
  -- El refresco debe ejecutarse después del COMMIT para ver los datos nuevos.
  pkg_mantenimiento.refrescar_mv('MV_VENTAS_MENSUALES');
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Regiones:      ' || pkg_mantenimiento.contar('REGIONES'));
  DBMS_OUTPUT.PUT_LINE('Países:        ' || pkg_mantenimiento.contar('PAISES'));
  DBMS_OUTPUT.PUT_LINE('Clientes:      ' || pkg_mantenimiento.contar('CLIENTES'));
  DBMS_OUTPUT.PUT_LINE('Productos:     ' || pkg_mantenimiento.contar('PRODUCTOS'));
  DBMS_OUTPUT.PUT_LINE('Pedidos:       ' || pkg_mantenimiento.contar('PEDIDOS'));
  DBMS_OUTPUT.PUT_LINE('Detalles:      ' || pkg_mantenimiento.contar('PEDIDO_DETALLE'));
  DBMS_OUTPUT.PUT_LINE('Pagos:         ' || pkg_mantenimiento.contar('PAGOS'));
  DBMS_OUTPUT.PUT_LINE('Auditoría:     ' || pkg_mantenimiento.contar('AUDITORIA_CAMBIOS'));
  DBMS_OUTPUT.PUT_LINE('Historial:     ' || pkg_mantenimiento.contar('PRECIOS_HISTORIAL'));
  DBMS_OUTPUT.PUT_LINE('=== Datos cargados ===');
END;
/

SHOW ERRORS
