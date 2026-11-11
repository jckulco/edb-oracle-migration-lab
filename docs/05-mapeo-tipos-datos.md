# 05. Mapeo de tipos de datos Oracle → EPAS

Migrar tipos no es cambiar nombres: es preservar **semántica**. Este documento
explica la decisión tomada en el laboratorio para cada tipo y los errores que
hay que evitar.

## Tabla maestra

| Oracle | EPAS / PostgreSQL | Decisión en el laboratorio | Riesgo |
|---|---|---|---|
| `NUMBER(p,s)` | `numeric(p,s)` | Exacto | Bajo |
| `NUMBER(p)` | `bigint` si es ID; `numeric(p)` si es métrica | IDs a `bigint` | Medio |
| `NUMBER` sin precisión | `numeric` | No usar `double` para dinero | Alto |
| `INTEGER` | `integer` / `bigint` | `bigint` en IDs | Bajo |
| `BINARY_FLOAT` | `real` | `productos.calificacion` | Bajo |
| `BINARY_DOUBLE` | `double precision` | No usado | Bajo |
| `VARCHAR2(n)` | `varchar(n)` | UTF-8; revisar semántica CHAR/BYTE | Medio |
| `NVARCHAR2(n)` | `varchar(n)` | Unicode | Bajo |
| `CHAR(n)` | `char(n)` | Códigos y banderas | Bajo |
| `CLOB` / `NCLOB` | `text` | `notas`, `datos_extra`, XML | Bajo |
| `BLOB` | `bytea` | `productos.imagen` | Medio (tamaño) |
| `RAW(n)` | `bytea` | `pagos.referencia` | Bajo |
| `LONG` | `text` | No usado; evitar | Alto |
| `DATE` (con hora) | `timestamp(0)` | Decisión explícita | **Alto** |
| `TIMESTAMP(n)` | `timestamp(n)` | Mantener precisión | Bajo |
| `TIMESTAMP WITH TIME ZONE` | `timestamptz` | Normalizar a UTC | Medio |
| `TIMESTAMP WITH LOCAL TIME ZONE` | `timestamptz` | Depende de zona de sesión | **Alto** |
| `INTERVAL DAY TO SECOND` | `interval day to second` | `pedidos.tiempo_entrega` | Bajo |
| `INTERVAL YEAR TO MONTH` | `interval` / columnas | No usado en tablas | Medio |
| `XMLTYPE` | `xml` | `productos.ficha_xml` | Medio |
| JSON nativo 23ai | `jsonb` | `datos_extra`, `atributos`, respuestas | Bajo |
| `BOOLEAN` 23ai | `boolean` | No usado en tablas | Bajo |
| `ROWID` / `UROWID` | sin equivalente | Usar PK | Alto |
| `SYS_REFCURSOR` | `refcursor` | Paquetes | Bajo |
| objeto con atributos | columnas / composite / `jsonb` | Dirección plana | **Alto** |
| nested table | `text[]` / tabla hija / `jsonb` | Teléfonos `text[]` | **Alto** |
| VARRAY | `text[]` / `jsonb` | No usado | Medio |

## Numéricos

### `NUMBER(p,s)`

`NUMBER(12,2)` se traduce a `numeric(12,2)`. Ambos son decimales exactos; no
uses `float` para dinero.

```sql
-- Oracle
precio NUMBER(12,2)
-- EPAS
precio numeric(12,2)
```

### `NUMBER(p)` e identificadores

Un `NUMBER(10)` que es una PK se traduce a `bigint` en el laboratorio. Es más
eficiente y evita comparar `numeric` con `bigint` en joins.

```sql
-- Oracle
cliente_id NUMBER(10) PRIMARY KEY
-- EPAS
cliente_id bigint PRIMARY KEY
```

Si el número puede superar 9.22e18, usa `numeric(38)`.

### `NUMBER` sin precisión

Oracle permite `NUMBER` sin escala; puede contener decimales. En EPAS usa
`numeric` sin precisión. Nunca lo mapees a `double precision` si representa
dinero o cantidades exactas.

### `BINARY_FLOAT` / `BINARY_DOUBLE`

Son binarios aproximados. Se mapean a `real` y `double precision`. No los uses
para montos. En el laboratorio `calificacion BINARY_FLOAT` → `real`.

## Caracteres

### `VARCHAR2(n)` y la semántica CHAR/BYTE

En Oracle:

```sql
nombre VARCHAR2(100 CHAR)  -- 100 caracteres, sin importar bytes
codigo VARCHAR2(100 BYTE)  -- 100 bytes
```

En PostgreSQL/EPAS, `varchar(n)` cuenta **caracteres**, no bytes. Para textos
Unicode, `VARCHAR2(100 BYTE)` no equivale a `varchar(100)`: puede aceptar más
caracteres de los que Oracle permitía. Revisa los `CHAR_USED` en
`USER_TAB_COLUMNS` si tu esquema usa `BYTE`.

```sql
-- Oracle
nombre VARCHAR2(120)
-- EPAS
nombre varchar(120)
```

### `CHAR(n)`

Se mantiene como `char(n)`. PostgreSQL rellena con espacios y los ignora en
comparaciones, igual que Oracle en la mayoría de los casos. Cuidado con
`CHAR` en índices y en igualdad con `VARCHAR`.

### `NVARCHAR2`

Se mapea a `varchar`/`text` con codificación UTF-8. EPAS/PostgreSQL no tienen
un tipo nacional separado.

## Fechas y horas

### `DATE` no es `date`

El error más común:

- Oracle `DATE` guarda fecha **y hora** (precisión de segundo).
- PostgreSQL `date` guarda solo fecha.

En el laboratorio, las columnas Oracle `DATE` que representan un instante se
mapean a `timestamp(0)`:

```sql
-- Oracle
fecha_alta DATE
-- EPAS
fecha_alta timestamp(0)
```

Si una columna realmente solo guarda fecha (sin hora), puedes usar `date` y
documentarlo. No mezcles ambos criterios sin revisar la aplicación.

### `TIMESTAMP(n)`

Se mantiene la precisión:

```sql
fecha_pedido TIMESTAMP(6)  →  timestamp(6)
```

### `TIMESTAMP WITH TIME ZONE`

Se mapea a `timestamptz`. Oracle guarda el instante y el desplazamiento; EPAS
guarda el instante en UTC y lo muestra en la zona de la sesión. El ETL
normaliza a UTC y la validación compara en UTC.

### `TIMESTAMP WITH LOCAL TIME ZONE`

Es el caso más delicado: Oracle normaliza al huso de la base y lo devuelve en
el huso de la sesión. En EPAS se mapea a `timestamptz`, pero el valor que ve
la aplicación depende de `TimeZone`.

Recomendación:

1. Estandarizar la sesión a UTC (`ALTER SESSION SET TIME_ZONE='UTC'` y
   `SET TIME ZONE 'UTC'`).
2. Migrar y validar en UTC.
3. Probar explícitamente los cambios de horario de verano.
4. Documentar qué zona usa la aplicación.

### `INTERVAL`

`INTERVAL DAY(3) TO SECOND(0)` → `interval day to second`.

```sql
-- Oracle
tiempo_entrega INTERVAL DAY(3) TO SECOND(0)
-- EPAS
tiempo_entrega interval day to second
```

`INTERVAL YEAR TO MONTH` no tiene una representación idéntica porque
PostgreSQL normaliza meses y días de forma distinta. Si lo usas, considera
columnas `years`/`months` o validar la aritmética caso por caso.

## LOBs y binarios

### `CLOB` → `text`

`text` es más simple que los Large Objects de PostgreSQL y funciona bien hasta
volúmenes razonables. Para cientos de MB por fila, evalúa `lo`/`bytea` y
streaming.

`DBMS_LOB` tiene equivalentes parciales en EPAS; revisa las funciones usadas.

### `BLOB` → `bytea`

`bytea` es adecuado para imágenes pequeñas/medianas. Para archivos grandes,
considera almacenamiento externo (S3, filesystem) y guardar solo la referencia.

### `RAW(n)` → `bytea`

`RAW(16)` se usa para GUIDs y hashes. `SYS_GUID()` produce 16 bytes; en EPAS
puedes generar `gen_random_uuid()` (extensión `pgcrypto`) si necesitas el
equivalente, pero el laboratorio copia el valor binario existente.

## XML y JSON

### `XMLTYPE` → `xml`

El tipo `xml` de PostgreSQL valida que el documento esté bien formado, pero no
tiene el mismo conjunto de funciones que Oracle (`XMLQUERY`, `XMLTABLE`,
`EXTRACTVALUE`). En el laboratorio el XML es simple y se migra como texto XML.

Preguntas antes de migrar:

- ¿Se consulta con XPath/XQuery?
- ¿Hay índices XML?
- ¿Se valida contra un esquema XSD?
- ¿El documento es grande?

### JSON en CLOB → `jsonb`

Oracle 23ai tiene tipo `JSON` nativo; el laboratorio usa `CLOB` con
`CHECK (... IS JSON)` para que el origen sea compatible con versiones previas.
En EPAS se usa `jsonb`:

- Binario, indexable con GIN.
- Operadores `->`, `->>`, `@>`, `?`.
- No conserva el orden de las claves ni los espacios.

Si la aplicación depende del texto exacto del JSON, usa `text` en lugar de
`jsonb`.

## Objetos y colecciones

### Objeto con atributos

Oracle:

```sql
direccion t_direccion
```

Opciones en EPAS:

1. **Columnas planas** (`dir_calle`, `dir_ciudad`, ...): simple, indexable y
   fácil de consultar. Es la elección del laboratorio.
2. **Tipo compuesto** (`CREATE TYPE t_direccion AS (...)`): conserva
   agrupación, pero complica el acceso desde la aplicación.
3. **`jsonb`**: flexible, pero pierde el esquema y la validación.

No hay una respuesta única; depende de cómo la aplicación lea y escriba el
atributo.

### Nested table

Oracle:

```sql
telefonos t_telefonos
```

Opciones:

1. **`text[]`**: conserva el orden y permite índices GIN. Es la elección del
   laboratorio.
2. **Tabla hija** (`cliente_telefonos`): mejor si cada teléfono tiene tipo,
   fecha de alta o reglas propias.
3. **`jsonb`**: si la colección es heterogénea.

La nested table también puede consultarse con `TABLE(...)`; esas consultas hay
que reescribirlas (`unnest` en EPAS).

## Identidades y secuencias

| Oracle | EPAS |
|---|---|
| `GENERATED BY DEFAULT AS IDENTITY` | `GENERATED BY DEFAULT AS IDENTITY` |
| `GENERATED ALWAYS AS IDENTITY` | `GENERATED ALWAYS AS IDENTITY` |
| `seq.NEXTVAL` | `nextval('seq')` |
| `seq.CURRVAL` | `currval('seq')` |

Después de cargar IDs explícitos, **hay que resincronizar**:

```sql
SELECT setval('seq_clientes',
              COALESCE((SELECT MAX(cliente_id) FROM clientes), 0) + 1,
              false);
```

Si no lo haces, la primera inserción nueva choca con una PK existente.

## Columnas virtuales y generadas

Oracle:

```sql
margen NUMBER(12,2) GENERATED ALWAYS AS (precio - costo) VIRTUAL
```

EPAS:

```sql
margen numeric(12,2) GENERATED ALWAYS AS (precio - costo) STORED
```

Diferencias:

- Oracle puede calcular en consulta (virtual); PostgreSQL/EPAS almacena
  (`STORED`).
- La expresión debe ser inmutable.
- No se pueden insertar valores en la columna generada.

## Defaults y `DEFAULT ON NULL`

Oracle `DEFAULT ON NULL` no existe en EPAS. Alternativas:

- `NOT NULL DEFAULT ...` si el valor nulo no es válido.
- Trigger `BEFORE INSERT` que reemplace `NULL`.
- `COALESCE` en la aplicación.

El laboratorio usa triggers para asignar secuencias y valores por defecto.

## Restricciones

| Oracle | EPAS |
|---|---|
| `CHECK` | `CHECK` |
| `UNIQUE` | `UNIQUE` |
| `PRIMARY KEY` | `PRIMARY KEY` |
| `FOREIGN KEY ... ON DELETE CASCADE` | Igual |
| `DEFERRABLE INITIALLY DEFERRED` | Igual |
| `ENABLE NOVALIDATE` | `NOT VALID` + `VALIDATE CONSTRAINT` |
| `DISABLE` | `ALTER TABLE ... DISABLE TRIGGER` (no equivalente exacto) |

En una migración grande, crea FKs después de la carga con `NOT VALID` y
valídalas luego. Así evitas bloquear escrituras durante mucho tiempo.

## Diferencias que sorprenden

### Mayúsculas y minúsculas

Oracle convierte identificadores no citados a mayúsculas; PostgreSQL/EPAS a
minúsculas. `VENTAS.CLIENTES` y `ventas.clientes` pueden ser el mismo objeto
lógico, pero las consultas escritas a mano deben ser consistentes.

- No uses identificadores citados (`"MiTabla"`) salvo que sea imprescindible.
- Configura `search_path` al esquema `ventas`.
- En EPAS, `CURRENT_USER` devuelve `ventas`; en Oracle `USER` devuelve
  `VENTAS`. El laboratorio usa `UPPER(CURRENT_USER)` para homogeneizar.

### Cadena vacía = NULL

Oracle trata `''` como `NULL`. PostgreSQL distingue `''` de `NULL`. Revisa
columnas `NOT NULL` y comparaciones `= ''`.

### Booleanos

Oracle 23ai agregó `BOOLEAN` en SQL, pero muchas aplicaciones usan `CHAR(1)`
(`'S'/'N'`). EPAS soporta `boolean`, pero el laboratorio conserva `CHAR(1)`
para no cambiar la API.

### `ROWID`

No migres `ROWID`. Usa la PK. Si la aplicación lo usa para actualizaciones
posicionales, hay que rediseñar esa lógica.

### `LONG`

Obsoleto en Oracle y problemático en herramientas. Convierte a `CLOB`/`text`
antes de migrar.

## Mapeo aplicado en este laboratorio

| Tabla.columna Oracle | Tipo EPAS | Nota |
|---|---|---|
| `clientes.direccion` | `dir_calle`, `dir_ciudad`, `dir_estado`, `dir_pais`, `dir_cp` | objeto plano |
| `clientes.telefonos` | `text[]` | nested table |
| `clientes.datos_extra` | `jsonb` | CLOB JSON |
| `clientes.fecha_alta` | `timestamp(0)` | DATE con hora |
| `productos.imagen` | `bytea` | BLOB |
| `productos.ficha_xml` | `xml` | XMLTYPE |
| `productos.atributos` | `jsonb` | CLOB JSON |
| `productos.calificacion` | `real` | BINARY_FLOAT |
| `productos.margen` | `numeric(12,2) GENERATED ... STORED` | virtual |
| `pedidos.tiempo_entrega` | `interval day to second` | INTERVAL |
| `pagos.referencia` | `bytea` | RAW(16) |
| `pagos.datos_respuesta` | `jsonb` | CLOB JSON |
| `auditoria_cambios.fecha` | `timestamptz` | TSLTZ, sesión UTC |

## Checklist de tipos

- [ ] ¿Cada `DATE` Oracle tiene hora? ¿Se mapeó a `timestamp(0)`?
- [ ] ¿Los `NUMBER` de dinero son `numeric`, no `float`?
- [ ] ¿Los IDs son `bigint` y las FKs coinciden?
- [ ] ¿`VARCHAR2` usaba `CHAR` o `BYTE`?
- [ ] ¿Los CLOB/BLOB caben en `text`/`bytea`?
- [ ] ¿Los JSON se consultan con operadores? ¿`jsonb` o `text`?
- [ ] ¿Los XML se consultan con XPath?
- [ ] ¿Los objetos y colecciones tienen un diseño destino?
- [ ] ¿Las secuencias se resincronizaron?
- [ ] ¿Las zonas horarias se probaron en UTC y en local?
- [ ] ¿La aplicación distingue `''` de `NULL`?
- [ ] ¿Hay `ROWID`, `LONG` o `UROWID` ocultos?

## Siguiente paso

[06-migracion-esquema.md](06-migracion-esquema.md): cómo se construye el DDL
destino y en qué orden.
