# EDB Migration Portal

Migration Portal es el servicio web de EDB que analiza un DDL Oracle, evalúa
la compatibilidad con EPAS, aplica correcciones y genera DDL compatible.

- URL: <https://migration.enterprisedb.com/>
- Requiere cuenta EDB.
- No se automatiza desde este repositorio porque es una aplicación web.

## 1. Exportar el DDL

```bash
make portal-export
```

Genera:

```text
migration/reports/portal/ventas_ddl.sql
migration/reports/portal/ventas_ddl.zip
migration/reports/portal/README.md
```

El DDL sale de `DBMS_METADATA` con storage/tablespace desactivados, e incluye
tipos, secuencias, tablas, constraints, índices, vistas, MVs, paquetes,
procedimientos, funciones y triggers.

## 2. Cargar en el Portal

1. Inicia sesión en <https://migration.enterprisedb.com/>.
2. Crea un proyecto.
3. Sube `ventas_ddl.sql` o el ZIP.
4. Selecciona **Create & assess**.
5. Revisa la tabla de compatibilidad:
   - Objetos al 100 %.
   - Objetos con errores o advertencias.
   - Correcciones automáticas aplicadas.
6. Para los objetos problemáticos, usa el **AI Copilot** o la Knowledge Base.
7. Aplica cambios y **Reassess**.
8. Descarga el DDL EPAS generado.

## 3. Contrastar con el laboratorio

El DDL descargado no se aplica a ciegas. Compáralo con:

- `sql/edb/01_tables.sql`
- `sql/edb/02_indexes.sql`
- `sql/edb/03_constraints.sql`
- `sql/edb/04_views.sql`
- `sql/edb/06_packages.sql`
- `sql/edb/08_triggers.sql`

Decisiones que el Portal puede tomar distinto:

- `DATE` → `timestamp` o `date`.
- Objetos → columnas planas o `jsonb`.
- Nested tables → tablas hijas o arreglos.
- Nombres en mayúsculas/minúsculas.
- `NUMBER` → `numeric`/`bigint`.
- Paquetes → funciones PL/pgSQL o paquetes EPAS.

## 4. AI Copilot

El Copilot ayuda a interpretar errores y proponer correcciones. Úsalo como
asistente, no como autoridad:

1. Pega el error y el DDL del objeto.
2. Pide una explicación y dos alternativas.
3. Verifica la propuesta contra la documentación de EPAS.
4. Aplícala en el laboratorio y ejecuta `make validate`.
5. Documenta la decisión.

Plantillas de prompts: `../copilot/prompts.md`.

## Limitaciones

- Analiza esquema, no datos.
- No conoce las reglas de negocio del laboratorio.
- Las correcciones automáticas pueden cambiar semántica.
- El DDL generado debe probarse y validarse.
- La carga de archivos muy grandes puede fallar en el navegador; divide por
  esquemas o usa un archivo más pequeño.

## Referencias

- <https://www.enterprisedb.com/docs/migration_portal/latest/>
- <https://www.enterprisedb.com/docs/migration_portal/latest/03_mp_using_portal/03_mp_quick_start/>
