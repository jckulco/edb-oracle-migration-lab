# 20. EDB Migration Portal y AI Copilot

## Qué es

Migration Portal es el servicio web de EDB que:

- Analiza el DDL de un esquema Oracle.
- Evalúa la compatibilidad con EPAS.
- Aplica correcciones automáticas.
- Genera DDL compatible.
- Marca objetos que requieren intervención manual.
- Ofrece AI Copilot para explicar errores y proponer alternativas.

URL: <https://migration.enterprisedb.com/>

## Flujo en el laboratorio

### 1. Exportar el DDL

```bash
make portal-export
```

El script:

1. Ejecuta `sql/oracle/13_export_portal_ddl.sql`.
2. Usa `DBMS_METADATA` para extraer tipos, secuencias, tablas, constraints,
   índices, vistas, MVs, paquetes, procedimientos, funciones y triggers.
3. Copia el archivo desde el contenedor.
4. Genera un ZIP y un README.

Salida:

```text
migration/reports/portal/
├── ventas_ddl.sql
├── ventas_ddl.zip
└── README.md
```

### 2. Crear el proyecto en el Portal

1. Inicia sesión.
2. Crea un proyecto.
3. Sube el `.sql` o el ZIP.
4. Selecciona **Create & assess**.

### 3. Revisar la evaluación

Mira:

- Porcentaje de compatibilidad por objeto.
- Errores y advertencias.
- Correcciones automáticas.
- Objetos que el Portal no pudo convertir.

Los objetos del laboratorio que probablemente requieran atención:

| Objeto | Motivo |
|---|---|
| `clientes.direccion` | Objeto Oracle con atributos |
| `clientes.telefonos` | Nested table |
| `mv_ventas_mensuales` | `REFRESH COMPLETE ON DEMAND`; no fast refresh |
| `pkg_auditoria` | `PRAGMA AUTONOMOUS_TRANSACTION` |
| `pkg_ventas` | `SYS_REFCURSOR`, `MERGE`, secuencias |
| `trg_clientes_aud` | Trigger Oracle con paquete autónomo |
| `bix_pedidos_moneda` | Índice bitmap |
| `pedidos.tiempo_entrega` | `INTERVAL DAY TO SECOND` |

### 4. AI Copilot

El Copilot está integrado en el Portal. Úsalo para:

- Explicar un error de conversión.
- Proponer alternativas para objetos/nested tables.
- Revisar paquetes y triggers.
- Entender una advertencia de compatibilidad.

Plantillas: `migration/edb-tools/copilot/prompts.md`.

Regla de oro: **probar toda sugerencia**. El Copilot no conoce tus datos, tus
reglas de negocio ni tu versión exacta de EPAS.

### 5. Descargar y contrastar

Descarga el DDL compatible. Compáralo con:

```text
sql/edb/01_tables.sql
sql/edb/02_indexes.sql
sql/edb/03_constraints.sql
sql/edb/04_views.sql
sql/edb/05_materialized_views.sql
sql/edb/06_packages.sql
sql/edb/08_triggers.sql
```

No reemplaces el DDL del laboratorio sin ejecutar:

```bash
make edb-schema
make migrate
make post-load
make validate
```

## Diferencias esperables frente al DDL del laboratorio

| Tema | Portal/MTK | Laboratorio |
|---|---|---|
| Objeto dirección | Puede aplanar o usar tipo | Columnas planas |
| Nested table | Tabla hija/array | `text[]` |
| Nombres | Minúsculas por defecto | Minúsculas |
| MV | Refresco completo | Refresco completo |
| Paquetes | Puede convertir a funciones | Paquetes EPAS |
| Bitmap | btree/BRIN | btree |
| `DATE` | `timestamp`/`date` | `timestamp(0)` |

Ninguna es “la correcta” en abstracto: depende de la aplicación y de las
pruebas.

## Limitaciones

- El Portal analiza esquema, no datos.
- No valida reglas de negocio.
- Las correcciones automáticas pueden cambiar semántica.
- El DDL generado no incluye la estrategia de secuencias/triggers del lab.
- La carga de archivos grandes puede fallar en el navegador.
- El Copilot puede alucinar; verifica siempre.

## Checklist

- [ ] `make portal-export` generó el DDL.
- [ ] El proyecto se creó y el DDL se subió.
- [ ] Se revisaron todos los objetos con errores.
- [ ] Se usó el Copilot solo como asistente.
- [ ] El DDL descargado se comparó con `sql/edb/`.
- [ ] Se ejecutó `make validate`.
- [ ] Las diferencias se documentaron.

## Referencias

- <https://www.enterprisedb.com/docs/migration_portal/latest/>
- <https://www.enterprisedb.com/docs/migration_portal/latest/03_mp_using_portal/03_mp_quick_start/>
- <https://www.enterprisedb.com/docs/migration_portal/latest/03_mp_using_portal/mp_ai_copilot/>
