# 00. Introducción

## La promesa y el problema

EDB Postgres Advanced Server (EPAS) se presenta como la opción de migración
Oracle más cercana: conserva paquetes PL/SQL, sinónimos funcionales, `NVL`,
`DECODE`, `CONNECT BY`, `ROWNUM`, `DUAL`, cursores y buena parte de la
semántica Redwood. La promesa es real, pero **migrar no es copiar tablas**.

Una migración Oracle → EPAS se rompe en los detalles:

- Un `DATE` Oracle guarda hora; un `date` PostgreSQL no.
- `VARCHAR2(100 CHAR)` no es lo mismo que `varchar(100)` en bytes.
- Un `NUMBER` sin precisión puede convertirse en `numeric` o en `double`.
- Un objeto Oracle con atributos no tiene una columna equivalente directa.
- Una `NESTED TABLE` no se copia con un `INSERT ... SELECT`.
- Un paquete con `PRAGMA AUTONOMOUS_TRANSACTION` necesita otra transacción.
- Un índice bitmap no existe en EPAS.
- Una vista materializada con `REFRESH FAST ON COMMIT` no tiene equivalente.
- Una secuencia Oracle y una identidad PostgreSQL se desincronizan después
  de cargar IDs explícitos.

Este repositorio construye un laboratorio completo para practicar cada uno de
esos puntos con datos reales, no con una sola tabla de ejemplo.

## Historia del laboratorio

Una empresa ficticia de ventas opera en Oracle Database Free 23ai. Su esquema
`VENTAS` tiene clientes, direcciones, catálogo, pedidos, pagos, empleados y
auditoría. La empresa quiere pasar a EPAS sin reescribir toda la aplicación.
El equipo de datos debe:

1. Entender qué objetos y tipos tiene.
2. Diseñar el esquema destino.
3. Migrar los datos sin perder LOBs, XML, JSON, binarios ni zonas horarias.
4. Reescribir lo que no es portable.
5. Validar fila a fila y función a función.
6. Medir el rendimiento y documentar el corte.

El repositorio es el artefacto de ese proyecto.

## Objetivos de aprendizaje

Al terminar el recorrido podrás:

- Levantar Oracle Database Free y EPAS con Docker Compose.
- Inspeccionar un esquema Oracle con el diccionario de datos.
- Decidir el tipo EPAS correcto para cada tipo Oracle, incluyendo LOBs, RAW,
  XMLTYPE, JSON, intervalos, objetos y colecciones.
- Migrar datos con `COPY` y un ETL en Python que no requiere Oracle Instant
  Client (`python-oracledb` en modo thin).
- Respetar el orden de carga y crear índices/FKs después de los datos.
- Migrar paquetes PL/SQL conservando la API pública.
- Recrear triggers, auditoría con transacción autónoma y secuencias.
- Comparar Oracle y EPAS con conteos, checksums y pruebas funcionales.
- Detectar y documentar las brechas que no tienen solución 1:1.
- Ejecutar un corte con checklist, rollback y plan de hypercare.

## Alcance

Incluido:

- Oracle Database Free 23ai en Docker.
- EDB Postgres Advanced Server 16 en Docker (imagen oficial de EDB adaptada
  para ejecutarse sola; requiere acceso al registro comercial).
- 12 tablas, 2 tipos definidos por el usuario, 5 secuencias, 3 identidades,
  20 índices Oracle, 6 vistas, 1 vista materializada, 4 paquetes, 3 objetos
  PL/SQL sueltos y 7 triggers.
- ETL, assessment, validación, benchmark y reportes.
- Documentación de decisiones, runbook y troubleshooting.

Fuera de alcance:

- Aplicación web o API de negocio.
- Réplica, alta disponibilidad o recuperación ante desastres.
- Migración de datos a escala de terabytes.
- Herramientas comerciales de EDB (Migration Portal, Barman, EFM, PEM).
- Oracle RAC, Exadata, Multitenant avanzado o características de pago.

## Cómo se relaciona con la promesa de EDB

El laboratorio muestra **qué tanto se conserva** y **qué hay que cambiar**.
La estrategia es deliberada:

1. Mantener la API de los paquetes (`pkg_ventas`, `pkg_util`, `pkg_auditoria`,
   `pkg_mantenimiento`) para que la aplicación cambie lo mínimo.
2. Conservar la sintaxis Oracle donde EPAS la soporta: paquetes, `%TYPE`,
   `NVL`, `DUAL`, `CONNECT BY`, `ROWNUM`, `MERGE`, triggers con `:NEW`/`:OLD`.
3. Reescribir solo lo que no es portable: `SYS_REFCURSOR` → `REFCURSOR`,
   `seq.NEXTVAL` → `nextval()`, `DBMS_MVIEW` → `REFRESH MATERIALIZED VIEW`,
   objetos → columnas planas, nested table → `text[]`, bitmap → btree/BRIN.
4. Validar que el resultado es equivalente, no solo que compila.

## Requisitos de honestidad

- EPAS es comercial. Sin una imagen/licencia válida, el laboratorio no puede
  ejecutar la parte EPAS.
- Los tiempos del benchmark son indicativos y dependen del hardware.
- El assessment es una heurística; no sustituye una revisión de negocio.
- Los datos son sintéticos; no contienen información personal real.
- La validación automática no cubre el 100 % de las reglas de negocio.

## Siguiente paso

Continúa con [01-arquitectura.md](01-arquitectura.md) o, si ya tienes todo
instalado, ve directo al [runbook](13-runbook.md).
