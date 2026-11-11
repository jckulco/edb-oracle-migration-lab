# 08. PL/SQL a EPAS

## La buena noticia

EPAS no es PostgreSQL “puro”: implementa un lenguaje SPL compatible con buena
parte de PL/SQL y añade paquetes, `%TYPE`, `%ROWTYPE`, cursores, excepciones
Oracle, `PRAGMA AUTONOMOUS_TRANSACTION`, `RAISE_APPLICATION_ERROR`, `NVL`,
`DECODE`, `DUAL`, `ROWNUM`, `CONNECT BY` y `MERGE`.

Eso permite conservar la API de negocio:

```sql
-- Oracle y EPAS
pkg_ventas.crear_pedido(3, 10, 2, v_pedido_id);
```

Pero no todo es idéntico. Este documento separa lo que se conserva de lo que
hay que revisar.

## Matriz de compatibilidad

| Construcción Oracle | EPAS 16 | Nota |
|---|---|---|
| `CREATE PACKAGE` / `BODY` | Sí | Requiere `edbspl`; usar `edb-psql` |
| `PROCEDURE` / `FUNCTION` | Sí | Sintaxis Oracle-style |
| `%TYPE` / `%ROWTYPE` | Sí | Validar en paquetes |
| Cursores explícitos | Sí | `CURSOR`, `OPEN`, `FETCH`, `CLOSE` |
| `SYS_REFCURSOR` | Parcial | Usar `REFCURSOR` en EPAS |
| `NO_DATA_FOUND`, `TOO_MANY_ROWS` | Sí | Nombres Oracle |
| `RAISE_APPLICATION_ERROR` | Sí | Códigos propios |
| `PRAGMA AUTONOMOUS_TRANSACTION` | Sí | Probar concurrencia |
| `EXECUTE IMMEDIATE` | Sí | Validar identificadores |
| `MERGE` | Sí | Sintaxis Oracle |
| `CONNECT BY` / `START WITH` | Sí | También existe `WITH RECURSIVE` |
| `ROWNUM` | Sí | También existe `LIMIT` |
| `DUAL` | Sí | Tabla de compatibilidad |
| `NVL`, `DECODE` | Sí | También `COALESCE`/`CASE` |
| `seq.NEXTVAL` | Parcial | Preferir `nextval('seq')` |
| `BULK COLLECT` / `FORALL` | Parcial | Soportado en SPL; validar rendimiento |
| `COMPOUND TRIGGER` | No | Rediseñar con triggers separados |
| `INSTEAD OF` | Parcial | Probar en vistas |
| `DBMS_OUTPUT` | Sí | Útil para depurar |
| `DBMS_LOB` | Parcial | Revisar funciones usadas |
| `DBMS_SCHEDULER` / `DBMS_JOB` | Parcial | Evaluar `pg_cron`/jobs |
| `DBMS_MVIEW.REFRESH` | No | Usar `REFRESH MATERIALIZED VIEW` |
| `UTL_FILE` | Parcial | Revisar rutas/permisos |
| `DBMS_RLS` | Parcial | EPAS tiene RLS/PG policies |
| Java en la base | No | Reescribir o externalizar |

La compatibilidad exacta depende de la versión de EPAS. Verifica en la
documentación de tu versión y prueba cada objeto.

## Paquetes

### Spec

```sql
CREATE OR REPLACE PACKAGE pkg_ventas AS
  c_iva CONSTANT NUMBER := 0.16;

  PROCEDURE crear_pedido(p_cliente_id  IN NUMBER,
                         p_producto_id IN NUMBER,
                         p_cantidad    IN NUMBER,
                         p_pedido_id   OUT NUMBER);

  FUNCTION total_pedido(p_pedido_id IN NUMBER) RETURN NUMBER;

  PROCEDURE listar_pedidos(p_cliente_id IN NUMBER,
                           p_cursor     OUT REFCURSOR);
END pkg_ventas;
```

### Body

```sql
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
END pkg_ventas;
```

### Cambios concretos respecto a Oracle

| Oracle | EPAS |
|---|---|
| `p_cursor OUT SYS_REFCURSOR` | `p_cursor OUT REFCURSOR` |
| `p_pedido_id := seq_pedidos.NEXTVAL` | `p_pedido_id := nextval('seq_pedidos')` |
| `EMPTY_CLOB()` | `''` |
| `USER` | `UPPER(CURRENT_USER)` |
| `TRUNC(SYSDATE)` | `CURRENT_DATE` o `date_trunc` |
| `TO_CHAR(p_id)` | `TO_CHAR(p_id)` |
| `p_id::text` | Evitar; usar `TO_CHAR` |

## Cursores y refcursors

Oracle:

```sql
OPEN p_cursor FOR
  SELECT pedido_id, total FROM pedidos WHERE cliente_id = p_cliente_id;
```

EPAS:

```sql
OPEN p_cursor FOR
  SELECT pedido_id, total FROM pedidos WHERE cliente_id = p_cliente_id;
```

El `OPEN ... FOR` es igual; el tipo del parámetro cambia.

Consumo desde Python/psycopg de un `REFCURSOR` es distinto al de Oracle; en el
laboratorio las pruebas funcionales usan funciones escalares para evitar
dependencias del driver.

## Excepciones

```sql
BEGIN
  SELECT activo INTO v_activo FROM clientes WHERE cliente_id = p_cliente_id;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20011, 'Cliente no encontrado');
  WHEN OTHERS THEN
    RAISE;
END;
```

EPAS reconoce `NO_DATA_FOUND`, `TOO_MANY_ROWS`, `ZERO_DIVIDE`, `DUP_VAL_ON_INDEX`
y otros nombres Oracle. Los códigos de error propios se lanzan con
`RAISE_APPLICATION_ERROR(-20xxx, ...)`.

Cuidado: no todas las excepciones Oracle tienen el mismo nombre/código. Prueba
los caminos de error, no solo el camino feliz.

## Transacciones autónomas

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

EPAS lo soporta. Implicaciones:

- La auditoría se confirma aunque la transacción principal haga rollback.
- Si el trigger falla, no debe tumbar la operación de negocio; el bloque
  `EXCEPTION` lo protege.
- Bajo alta concurrencia, una transacción autónoma por fila puede ser costosa.
  Considera una cola/tabla de auditoría y un proceso por lotes.

## SQL dinámico

Oracle:

```sql
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM "' || UPPER(p_tabla) || '"' INTO v_count;
```

EPAS:

```sql
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || quote_ident(p_tabla) INTO v_count;
```

Reglas:

1. Nunca concatenes entrada de usuario sin validar.
2. Usa una lista blanca o una expresión regular.
3. Prefiere `quote_ident`/`format('%I')` para identificadores.
4. Para valores, usa parámetros, no concatenación.

## MERGE

Oracle y EPAS comparten la sintaxis:

```sql
MERGE INTO clientes c
USING (SELECT p_cliente_id AS id FROM dual) s
   ON (c.cliente_id = s.id)
WHEN MATCHED THEN
  UPDATE SET nombre = p_nombre, email = p_email
WHEN NOT MATCHED THEN
  INSERT (cliente_id, codigo, nombre, email, fecha_alta, segmento, activo)
  VALUES (p_cliente_id, 'CLI-' || LPAD(p_cliente_id, 5, '0'),
          p_nombre, p_email, CURRENT_DATE, 'C', 'S');
```

Valida el `MERGE` bajo concurrencia: puede haber carrera entre el `ON` y el
`INSERT`. En cargas masivas, `INSERT ... ON CONFLICT` de PostgreSQL puede ser
más simple.

## `CONNECT BY`, `ROWNUM`, `DUAL`, `NVL`, `DECODE`

EPAS los soporta en su capa Redwood. El laboratorio los usa en:

- `vw_jerarquia_empleados` (`CONNECT BY`, `LEVEL`).
- `vw_ultimos_pedidos` (`ROWNUM` en Oracle, `LIMIT` en EPAS).
- `pkg_ventas` (`NVL`, `DUAL` en `MERGE`).

Para código nuevo, prefiere estándar:

| Oracle | Estándar |
|---|---|
| `NVL(a,b)` | `COALESCE(a,b)` |
| `DECODE(x, ...)` | `CASE` |
| `ROWNUM <= 10` | `LIMIT 10` |
| `CONNECT BY` | `WITH RECURSIVE` |
| `DUAL` | `SELECT ...` sin `FROM` |
| `seq.NEXTVAL` | `nextval('seq')` |

## `BULK COLLECT` y `FORALL`

EPAS documenta soporte de `FORALL` y procesamiento masivo, pero el rendimiento
y los tipos de colección pueden variar. El laboratorio no los usa en la ruta
crítica; si tu código Oracle depende de ellos:

1. Compila y prueba con el volumen real.
2. Compara tiempos contra `INSERT ... SELECT`.
3. Revisa el uso de `LIMIT`, `SAVE EXCEPTIONS` y colecciones asociativas.
4. Considera reescribir a SQL basado en conjuntos.

## Triggers

La sintaxis Oracle se conserva:

```sql
CREATE TRIGGER trg_pedido_detalle_biu
BEFORE INSERT OR UPDATE ON pedido_detalle
FOR EACH ROW
BEGIN
  :NEW.total_linea := ROUND(:NEW.cantidad * :NEW.precio_unitario, 2);
END;
```

No soportadas o parciales:

- `COMPOUND TRIGGER`.
- `FOLLOWS` / `PRECEDES` (orden explícito).
- `INSTEAD OF` en vistas complejas.
- Triggers de sistema (`LOGON`, `DDL`).

Alternativas: varios triggers con orden de creación, reglas, o mover la lógica
a la aplicación.

## Compilación y depuración

```bash
# Cargar paquetes
docker compose --env-file .env -f docker/compose.yaml exec -T edb \
  edb-psql -X -v ON_ERROR_STOP=1 -U ventas -d ventas -f - \
  < sql/edb/06_packages.sql
```

Si `psql` genérico falla con `syntax error at or near ";"`, usa `edb-psql`.

Para ver errores de compilación, `edb-psql` los muestra en la salida. También:

```sql
SELECT p.proname, p.prokind
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'ventas'
 ORDER BY 1;
```

`DBMS_OUTPUT`:

```sql
SET SERVEROUTPUT ON;  -- en SQL*Plus
-- En EPAS, DBMS_OUTPUT escribe en la salida del cliente si está habilitado.
```

El laboratorio usa `pkg_util.log` para mensajes; no dependas de él para
pruebas automáticas.

## Errores frecuentes

| Error | Causa | Solución |
|---|---|---|
| `syntax error at or near ";"` | `psql` genérico no entiende paquetes | Usar `edb-psql` |
| `package ... does not exist` | `edbspl` no instalado | `CREATE EXTENSION edbspl;` |
| `column ... does not exist` | `%TYPE` sobre tabla mal calificada | Revisar `search_path` y nombre |
| `function ... does not exist` | Paquete no compilado o firma distinta | Revisar spec/body |
| `cursor ... is not open` | Refcursor mal manejado | Revisar `OPEN`/`CLOSE` |
| `cannot commit while a subtransaction is active` | Autónoma mal usada | Revisar `PRAGMA` y bloques |
| `query has no destination for result data` | `SELECT` sin `INTO` en SPL | Añadir `INTO` o `PERFORM` |
| `too many rows` | `SELECT INTO` devuelve >1 | Añadir filtro o cursor |

## Estrategia de migración de PL/SQL

1. Inventariar objetos y dependencias (`USER_DEPENDENCIES`).
2. Congelar la API pública (nombres, parámetros, tipos de retorno).
3. Migrar primero utilidades y auditoría.
4. Migrar paquetes de negocio.
5. Migrar triggers al final, después de la carga.
6. Compilar todo con `edb-psql`.
7. Ejecutar pruebas funcionales comparando Oracle vs EPAS.
8. Medir los caminos críticos.

## Checklist de PL/SQL

- [ ] ¿Todos los paquetes compilan?
- [ ] ¿La API pública se conserva?
- [ ] ¿Los `REFCURSOR` se probaron?
- [ ] ¿Las excepciones se comportan igual?
- [ ] ¿Las transacciones autónomas no duplican auditoría?
- [ ] ¿El SQL dinámico valida identificadores?
- [ ] ¿Los triggers se crean después de la carga?
- [ ] ¿`BULK COLLECT`/`FORALL` tienen prueba de carga?
- [ ] ¿Los `DBMS_*` usados existen en tu versión de EPAS?
- [ ] ¿Las pruebas funcionales cubren los errores, no solo el camino feliz?

## Siguiente paso

[09-indices-rendimiento.md](09-indices-rendimiento.md).
