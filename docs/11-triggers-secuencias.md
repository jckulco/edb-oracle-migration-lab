# 11. Triggers y secuencias

## Triggers

### Lo que se conserva

EPAS acepta la sintaxis Oracle:

```sql
CREATE TRIGGER trg_pedido_detalle_biu
BEFORE INSERT OR UPDATE ON pedido_detalle
FOR EACH ROW
BEGIN
  :NEW.total_linea := ROUND(
    :NEW.cantidad * :NEW.precio_unitario *
    (1 - COALESCE(:NEW.descuento_pct, 0) / 100), 2);
END;
```

También `AFTER`, `FOR EACH ROW`, `:OLD`, `:NEW`, `WHEN`, `DECLARE` y bloques
de excepción.

### Lo que cambia

| Oracle | EPAS | Acción |
|---|---|---|
| `COMPOUND TRIGGER` | No soportado | Dividir en varios triggers |
| `FOLLOWS` / `PRECEDES` | Parcial | Ordenar por creación o rediseñar |
| `INSTEAD OF` | Parcial | Probar en vistas |
| Trigger de sistema (`LOGON`, `DDL`) | No | Usar event triggers de PG |
| `UPDATING('COL')` | Parcial | Usar `IF :OLD.col <> :NEW.col` |
| Trigger con `PRAGMA AUTONOMOUS_TRANSACTION` | Sí | Probar concurrencia |

### Triggers del laboratorio

| Trigger | Evento | Lógica |
|---|---|---|
| `trg_clientes_bi` | BEFORE INSERT | `nextval`, defaults |
| `trg_clientes_aud` | AFTER I/U/D | `pkg_auditoria.registrar` |
| `trg_direcciones_bi` | BEFORE INSERT | `nextval` |
| `trg_productos_precio` | AFTER UPDATE | historial + auditoría |
| `trg_pedidos_bi` | BEFORE I/U | validar cliente/estado/total |
| `trg_pedido_detalle_biu` | BEFORE I/U | calcular `total_linea` |
| `trg_pagos_bi` | BEFORE INSERT | `nextval`, fecha |

### Auditoría con transacción autónoma

```sql
PROCEDURE registrar(...) IS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO auditoria_cambios (...) VALUES (...);
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Auditoría: ' || SQLERRM);
END;
```

Consecuencias:

- Si la transacción principal hace rollback, la auditoría permanece.
- Si el trigger de auditoría falla, no debe tumbar la operación de negocio.
- Bajo carga, cada evento abre/cierra una transacción; mide el impacto.

### Orden de creación

Los triggers se crean después de la carga:

```text
tablas → COPY → índices → FKs → vistas → MV → paquetes → triggers
```

Si se crearan antes, la carga dispararía auditoría e historial, duplicando los
datos que ya vienen de Oracle.

### Deshabilitar triggers

En PostgreSQL/EPAS:

```sql
ALTER TABLE pedidos DISABLE TRIGGER trg_pedidos_bi;
ALTER TABLE pedidos ENABLE TRIGGER trg_pedidos_bi;
```

Requiere ser dueño de la tabla. `DISABLE TRIGGER ALL` puede desactivar también
los triggers de integridad; úsalo con cuidado y solo en una carga controlada.

Alternativa para cargas masivas: cargar antes de crear los triggers, como hace
el laboratorio.

### Trigger de historial de precios

```sql
CREATE TRIGGER trg_productos_precio
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
  IF :OLD.precio <> :NEW.precio THEN
    INSERT INTO precios_historial (...)
    VALUES (nextval('seq_historial'), :NEW.producto_id, :OLD.precio,
            :NEW.precio, CURRENT_TIMESTAMP, UPPER(CURRENT_USER));
  END IF;
END;
```

Prueba:

```sql
UPDATE productos SET precio = precio * 1.10 WHERE producto_id = 7;
SELECT * FROM precios_historial WHERE producto_id = 7 ORDER BY fecha DESC;
```

## Secuencias

### Mapeo

| Oracle | EPAS |
|---|---|
| `CREATE SEQUENCE seq START WITH 1 INCREMENT BY 1 CACHE 20` | `CREATE SEQUENCE seq START WITH 1 INCREMENT BY 1` |
| `seq.NEXTVAL` | `nextval('seq')` |
| `seq.CURRVAL` | `currval('seq')` |
| `seq.NEXTVAL` en trigger | `nextval('seq')` |
| Identity | Identity |

### Resincronización

El ETL inserta IDs explícitos. Sin resync, la secuencia empieza en 1 y choca
con la PK existente.

```sql
SELECT setval('seq_pedidos',
              COALESCE((SELECT MAX(pedido_id) FROM pedidos), 0) + 1,
              false);
```

El tercer argumento `false` indica que el próximo `nextval` devuelve ese valor
(no el siguiente).

Identidades:

```sql
SELECT setval(pg_get_serial_sequence('productos', 'producto_id'),
              COALESCE((SELECT MAX(producto_id) FROM productos), 0) + 1,
              false);
```

### Huecos y caché

- Las secuencias no garantizan continuidad: puede haber huecos por rollback,
  caché o reinicios.
- Oracle `CACHE 20` y EPAS `CACHE 1` cambian el rendimiento y los huecos.
- No uses secuencias para numeración legal/fiscal sin una tabla de control.
- Para IDs expuestos al usuario, evalúa un esquema de numeración propio.

### `IDENTITY` vs secuencia + trigger

Ventajas de `IDENTITY`:

- Menos código.
- El motor gestiona la secuencia.
- `RETURNING` funciona igual.

Ventajas de secuencia + trigger:

- Control explícito.
- Compatibilidad con código Oracle que espera `seq.NEXTVAL`.
- Permite reglas adicionales en el trigger.

El laboratorio usa ambos para comparar.

### `currval` y sesión

`currval('seq')` solo es válido en la sesión que llamó a `nextval`. No lo uses
en otra conexión. En un pool, asegúrate de que la operación ocurre en la misma
sesión.

## Pruebas de triggers y secuencias

```sql
-- Nueva fila sin ID
INSERT INTO pagos (pedido_id, metodo, monto, confirmado)
VALUES (1, 'EFECTIVO', 10, 'S')
RETURNING pago_id;

-- Debe ser mayor que el máximo existente
SELECT MAX(pago_id) FROM pagos;
```

```sql
-- Historial
UPDATE productos SET precio = precio + 1 WHERE producto_id = 10;
SELECT COUNT(*) FROM precios_historial WHERE producto_id = 10;
```

```sql
-- Auditoría
SELECT COUNT(*) FROM auditoria_cambios WHERE tabla = 'CLIENTES';
```

## Errores frecuentes

| Error | Causa | Solución |
|---|---|---|
| `duplicate key value violates unique constraint` | Secuencia sin resync | `setval` |
| `null value in column ... violates not-null` | Trigger no asignó el ID | Revisar `BEFORE INSERT` |
| `stack depth limit exceeded` | Trigger recursivo | Evitar `UPDATE` sobre la misma tabla |
| `cannot execute ... in a read-only transaction` | Trigger en standby/réplica | No escribir en réplicas |
| Auditoría duplicada | Trigger creado antes de la carga | Recrear orden |
| `permission denied for sequence` | Falta `USAGE` | Otorgar `USAGE` al usuario |
| `currval is not yet defined` | No hubo `nextval` en la sesión | Llamar `nextval` primero |

## Checklist de triggers y secuencias

- [ ] ¿Los triggers se crean después de la carga?
- [ ] ¿La auditoría es autónoma y no bloquea el negocio?
- [ ] ¿Los triggers no se llaman recursivamente?
- [ ] ¿Las secuencias se resincronizaron?
- [ ] ¿Las identidades se resincronizaron?
- [ ] ¿Los huecos son aceptables para el negocio?
- [ ] ¿Se probaron inserts concurrentes?
- [ ] ¿Se midió el coste de los triggers?

## Siguiente paso

[12-validacion.md](12-validacion.md).
