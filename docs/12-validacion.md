# 12. Validación

## Qué significa “migración exitosa”

No es que el DDL compile ni que `COPY` termine. Es que:

1. Están todas las filas.
2. Los valores son equivalentes.
3. Las reglas de negocio siguen funcionando.
4. Los objetos PL/SQL responden igual.
5. El rendimiento es aceptable.
6. Hay evidencia reproducible.

El laboratorio automatiza los puntos 1–4 y deja los puntos 5–6 a los reportes
y al checklist de cutover.

## Niveles de validación

| Nivel | Qué compara | Herramienta |
|---|---|---|
| Conteos | Filas por tabla | `validate.py` |
| Nulos | Nulos por columna | `validate.py` |
| Checksums | Hash canónico por fila | `validate.py` |
| Integridad | FKs huérfanas | SQL / constraints |
| Funcional | Paquetes, funciones y vistas | `functional.py` |
| Rendimiento | Tiempos y planes | `benchmark.py`, `EXPLAIN` |
| Negocio | Reglas y totales | Consultas + UAT |

## Cómo se ejecuta

```bash
make validate
```

Salida esperada:

```text
Validando 12 tablas...
  regiones                OK
  paises                  OK
  clientes                OK
  ...
  precios_historial       OK
Ejecutando pruebas funcionales...
Pruebas funcionales: 18/18 OK
------------------------------------------------------------------------------
Reporte: migration/reports/validation.md
JSON:    migration/reports/validation.json
Resultado global: OK
```

Si hay diferencias, el comando sale con código 1.

## Checksums canónicos

Para cada fila:

1. Se normaliza cada valor según el tipo destino.
2. Se convierte a una representación canónica:
   - `numeric`: sin ceros finales (`1.20` y `1.2` son iguales).
   - `jsonb`: claves ordenadas.
   - `timestamptz`: UTC.
   - `bytea`: hexadecimal.
   - `text[]`: JSON ordenado.
   - `interval`: segundos totales.
3. Se calcula SHA-256 de la concatenación con longitud.

Así se evitan falsos positivos por diferencias de formato entre motores.

### Qué no detecta

- Diferencias de rendimiento.
- Diferencias de semántica en funciones no probadas.
- Datos que no están en el manifiesto.
- Reglas de negocio que no se expresaron como prueba.
- Diferencias de collation/orden no usadas en el hash.

## Conteos y nulos

`validate.py` compara:

- `COUNT(*)` de origen y destino.
- `COUNT(columna)` por columna (nulos).
- PKs faltantes/sobrantes.
- Hasta 10 diferencias por tabla, con columna y valores.

Si una tabla falla por conteo, revisa primero:

```bash
cat migration/reports/data_load.json
```

y luego:

```sql
-- Oracle
SELECT COUNT(*) FROM pedidos;
-- EPAS
SELECT COUNT(*) FROM ventas.pedidos;
```

## Integridad referencial

Las FKs se validan al crear el esquema. Consultas manuales:

```sql
-- Pedidos sin cliente
SELECT COUNT(*)
  FROM ventas.pedidos p
  LEFT JOIN ventas.clientes c ON c.cliente_id = p.cliente_id
 WHERE c.cliente_id IS NULL;

-- Detalles sin pedido
SELECT COUNT(*)
  FROM ventas.pedido_detalle d
  LEFT JOIN ventas.pedidos p ON p.pedido_id = d.pedido_id
 WHERE p.pedido_id IS NULL;

-- Pagos sin pedido
SELECT COUNT(*)
  FROM ventas.pagos pg
  LEFT JOIN ventas.pedidos p ON p.pedido_id = pg.pedido_id
 WHERE p.pedido_id IS NULL;
```

Todas deben devolver 0.

## Pruebas funcionales

`migration/config/functional_tests.yaml` define pruebas no destructivas:

```yaml
- id: descuento_cliente_a
  oracle: "SELECT pkg_ventas.descuento_cliente(3, 10000) FROM dual"
  edb: "SELECT pkg_ventas.descuento_cliente(3, 10000)"
  expected: 800
```

Cada prueba:

1. Ejecuta la consulta en Oracle.
2. Ejecuta la consulta en EPAS.
3. Canoniza ambos resultados.
4. Compara con `expected` si existe.

Cobertura del laboratorio:

- Descuentos por segmento.
- Totales de pedido.
- Estados.
- Formato de moneda.
- Día hábil.
- Impuesto.
- Promedio de ventas.
- Vistas (clientes activos, jerarquía, top productos, últimos pedidos).
- MV.
- Agregados de negocio.
- Auditoría.
- Conteo dinámico.

## Reglas de negocio adicionales

Además de las pruebas, revisa:

```sql
-- Totales cuadran con el detalle
SELECT COUNT(*)
  FROM ventas.pedidos p
 WHERE p.total <> (
   SELECT COALESCE(SUM(d.total_linea), 0)
     FROM ventas.pedido_detalle d
    WHERE d.pedido_id = p.pedido_id
 );

-- Impuesto del 16 %
SELECT COUNT(*)
  FROM ventas.pedidos
 WHERE impuesto <> ROUND((subtotal - descuento) * 0.16, 2);

-- Pagos que exceden el total
SELECT COUNT(*)
  FROM ventas.pagos pg
  JOIN ventas.pedidos p ON p.pedido_id = pg.pedido_id
 WHERE pg.monto > p.total + 0.01;
```

El laboratorio siembra datos consistentes; si alguna consulta devuelve >0,
hay un bug en la semilla o en la migración.

## Evidencia

`migration/reports/validation.md` incluye:

- Resultado global.
- Tabla por tabla con conteos y estado.
- Detalle de fallos (PK, columna, valor origen/destino).
- Pruebas funcionales con resultado.

`migration/reports/validation.json` es apto para CI o para adjuntar a un
ticket de cambio.

## Validación con herramientas EDB

Además del validador propio, puedes usar **EDB LiveCompare** para comparar
Oracle y EPAS fila a fila:

```bash
make livecompare-grant   # otorga grants y compara
```

LiveCompare y `validate.py` son complementarios: el primero aporta la mirada
de la herramienta comercial; el segundo, checksums canónicos y pruebas de
negocio. Detalles en [21-livecompare.md](21-livecompare.md).

## Criterios de aceptación

| Criterio | Umbral |
|---|---|
| Conteos | 100 % iguales |
| Checksums | 100 % iguales |
| Nulos | 100 % iguales |
| FKs | 0 huérfanas |
| Pruebas funcionales | 100 % OK |
| Diferencias conocidas | Documentadas y aprobadas |
| Rendimiento | Sin regresión > 20 % en consultas críticas |
| UAT | Firmada por negocio |

El umbral de rendimiento es una guía; ajústalo a tu caso.

## Limitaciones

- El validador carga las filas en memoria. Para tablas enormes, usa checksums
  por rangos de PK y cursores.
- No valida tipos no incluidos en el manifiesto.
- No prueba concurrencia ni transacciones.
- No sustituye pruebas de la aplicación.
- Las pruebas funcionales son de solo lectura; las escrituras se prueban en
  UAT.

## Cómo investigar una diferencia

1. Identifica la tabla y la PK en `validation.md`.
2. Consulta la fila en ambos motores.
3. Revisa el tipo destino y la normalización.
4. Comprueba si el valor se generó por un trigger/default.
5. Si es una diferencia aceptable, documéntala y exclúyela con justificación.
6. Si es un bug, corrige el ETL o la semilla y vuelve a migrar.

## Checklist de validación

- [ ] `make migrate` terminó sin errores.
- [ ] `make post-load` creó todos los objetos.
- [ ] `make validate` da `OK`.
- [ ] No hay FKs huérfanas.
- [ ] Las pruebas funcionales pasan.
- [ ] Los reportes están archivados.
- [ ] Las diferencias conocidas están documentadas.
- [ ] El negocio firmó los totales.

## Siguiente paso

[13-runbook.md](13-runbook.md): el recorrido completo, comando a comando.
