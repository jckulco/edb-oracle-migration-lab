# Prompts para Migration Portal AI Copilot

El Copilot es un asistente dentro del ecosistema de EDB. No sustituye la
prueba en el laboratorio. Usa estos prompts como punto de partida.

## 1. Explicar un error de conversión

```text
Estoy migrando Oracle 23ai a EDB Postgres Advanced Server 16.
El objeto <NOMBRE> falla con este error:
<ERROR>

DDL Oracle:
<DDL>

DDL generado por el Portal:
<DDL>

Explícame la causa raíz y dame dos alternativas compatibles con EPAS.
Indica qué cambia en la aplicación y cómo probarlo.
```

## 2. Objeto con atributos

```text
Tengo una columna Oracle de tipo objeto T_DIRECCION (calle, ciudad, estado,
pais, codigo_postal). La aplicación la lee como direccion.ciudad.
¿Qué opciones tengo en EPAS: columnas planas, tipo compuesto o jsonb?
Compara impacto en consultas, índices y cambios de código.
```

## 3. Nested table

```text
Tengo una nested table T_TELEFONOS en Oracle y la aplicación consulta
TABLE(telefonos). ¿Cómo la represento en EPAS: text[], tabla hija o jsonb?
Dame el DDL, el código de lectura/escritura y las pruebas necesarias.
```

## 4. Paquete con autonomous transaction

```text
Este paquete Oracle escribe auditoría con PRAGMA AUTONOMOUS_TRANSACTION.
En EPAS, ¿qué debo revisar para que no bloquee la transacción principal ni
duplique filas? Dame un ejemplo y una prueba de concurrencia.
```

## 5. Vista materializada

```text
Tengo una MV Oracle con REFRESH FAST ON COMMIT. En EPAS no existe ese modo.
Propón una estrategia de refresco (completo, concurrente, programado) y
explica el impacto en la aplicación.
```

## 6. Índice bitmap

```text
Tengo un bitmap index sobre una columna de baja cardinalidad. ¿Qué alternativa
recomiendas en EPAS: btree, BRIN, índice parcial o particionamiento? Justifica
con el patrón de consulta y de escritura.
```

## 7. Reglas de uso

- Pega solo DDL/datos sintéticos, nunca información real.
- Pide siempre una explicación y una forma de verificación.
- Contrasta con la documentación oficial de EPAS.
- Aplica el cambio en una rama y ejecuta `make validate`.
- Documenta la decisión en `docs/06-migracion-esquema.md`.
