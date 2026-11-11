# 13. Runbook

Este es el recorrido completo, de cero a validación. Ejecuta los comandos
desde la raíz del repositorio.

## 0. Preflight

```bash
git clone <URL_DEL_REPOSITORIO> edb-oracle-migration-lab
cd edb-oracle-migration-lab

cp .env.example .env
# Edita .env:
#   - contraseñas
#   - EDB_IMAGE (tag autorizado)
#   - puertos si hay conflicto

make venv
make check
```

Checkpoint: `make check` no debe reportar errores. Si Docker no responde,
inicia Docker Desktop/Engine.

## 1. Autenticación EDB

Solo si usas el registro oficial:

```bash
export EDB_TOKEN='...'
docker login docker.enterprisedb.com --username k8s --password-stdin <<< "$EDB_TOKEN"
```

Checkpoint: `Login Succeeded`.

## 2. Levantar la infraestructura

```bash
make up
```

La primera vez:

- Descarga Oracle Free.
- Construye la imagen EPAS.
- Inicializa Oracle (varios minutos).
- Inicializa EPAS (`initdb`, usuarios, esquema).

Checkpoint:

```bash
make ps
docker inspect -f '{{.State.Health.Status}}' lab-oracle
docker inspect -f '{{.State.Health.Status}}' lab-edb
```

Ambos deben decir `healthy`.

## 3. Cargar Oracle

```bash
make oracle-load
```

Esto ejecuta, en orden:

```text
00_reset.sql
01_types.sql
02_tables.sql
03_sequences.sql
04_indexes.sql
05_constraints.sql
06_views.sql
07_materialized_views.sql
08_packages.sql
09_standalone.sql
10_triggers.sql
11_seed.sql
12_validation_queries.sql
```

Checkpoint: verás conteos como 60 clientes, 40 productos, 300 pedidos y las
pruebas rápidas de paquetes al final.

Si falla, revisa:

```bash
make logs
# o
docker compose --env-file .env -f docker/compose.yaml logs --tail=100 oracle
```

## 4. Assessment

```bash
make assess
```

Genera:

- `migration/reports/assessment.md`
- `migration/reports/assessment.json`

Checkpoint: revisa los hallazgos `ALTO` y `MEDIO`. No continúes sin entender
los objetos/nested tables, MVs, bitmap e intervalos.

## 5. Crear el esquema destino

```bash
make edb-schema
```

Esto ejecuta `00_reset.sql` (destructivo) y `01_tables.sql` en EPAS.

Checkpoint:

```bash
docker compose --env-file .env -f docker/compose.yaml exec edb \
  edb-psql -U ventas -d ventas -c '\dt ventas.*'
```

Debes ver 12 tablas.

## 6. Migrar datos

```bash
make migrate
```

Por defecto trunca y carga todas las tablas. Para ver los conteos sin escribir:

```bash
make migrate -- --dry-run
```

Checkpoint: el reporte `migration/reports/data_load.json` no debe tener tablas
con error. Los conteos deben coincidir con Oracle.

## 7. Post-carga

```bash
make post-load
```

Crea:

- Índices.
- FKs (`NOT VALID` + `VALIDATE`).
- Vistas.
- MV.
- Paquetes.
- Funciones/procedimientos sueltos.
- Triggers.
- Resync de secuencias y `ANALYZE`.

Checkpoint:

```bash
docker compose --env-file .env -f docker/compose.yaml exec edb \
  edb-psql -U ventas -d ventas -c '\dv ventas.*'
```

Y prueba una función:

```bash
docker compose --env-file .env -f docker/compose.yaml exec edb \
  edb-psql -U ventas -d ventas \
  -c "SELECT pkg_ventas.descuento_cliente(3, 10000);"
```

Debe devolver `800.00` (o `800`).

## 8. Validar

```bash
make validate
```

Checkpoint: `Resultado global: OK` y `18/18` pruebas funcionales (el número
puede variar si agregas pruebas).

Si falla, abre `migration/reports/validation.md`.

## 9. Benchmark

```bash
make benchmark
```

Genera `migration/reports/benchmark.md`. Recuerda que es indicativo.

## 10. Herramientas EDB (opcional)

Si tienes las herramientas comerciales instaladas:

```bash
make tools-check        # qué hay disponible
make portal-export      # DDL para Migration Portal
make mtk-schema         # DDL offline con MTK
make edbldr-demo        # carga con EDB*Loader
make livecompare-grant  # comparación con LiveCompare
```

Detalles: [18-herramientas-edb.md](18-herramientas-edb.md).

## 11. Flujo completo

```bash
make env
make venv
make check
# docker login ...
make up
make oracle-load
make assess
make edb-schema
make migrate
make post-load
make validate
make benchmark
```

O:

```bash
make all
make validate
```

## 12. Reconstruir desde cero

```bash
make reset
```

Borra volúmenes, levanta, carga Oracle, crea EPAS, migra y hace post-carga.
No ejecuta la validación final para que puedas revisar los reportes.

## 13. Detener

```bash
make down                 # conserva datos
./scripts/09_down.sh --volumes  # borra datos
```

## Tiempos orientativos

| Paso | Primera vez | Con imágenes/caché |
|---|---|---|
| `make up` | 5–15 min | 1–3 min |
| `make oracle-load` | 1–3 min | 1–2 min |
| `make assess` | < 10 s | < 10 s |
| `make edb-schema` | < 5 s | < 5 s |
| `make migrate` | 10–60 s | 10–60 s |
| `make post-load` | 5–20 s | 5–20 s |
| `make validate` | 10–60 s | 10–60 s |

Dependen de CPU, RAM, Docker y de si la imagen EPAS corre emulada.

## Puntos de control

- [ ] `.env` con credenciales y `EDB_IMAGE`.
- [ ] `make check` OK.
- [ ] `make up` con dos `healthy`.
- [ ] `make oracle-load` con conteos.
- [ ] `make assess` con hallazgos revisados.
- [ ] `make edb-schema` con 12 tablas.
- [ ] `make migrate` sin errores.
- [ ] `make post-load` sin errores.
- [ ] `make validate` OK.
- [ ] Reportes archivados.

## Si algo falla

1. No borres volúmenes todavía.
2. `make ps` y `make logs`.
3. Revisa `migration/reports/*.json`.
4. Consulta [14-troubleshooting.md](14-troubleshooting.md).
5. Si es un error de datos, corrige y repite desde `make edb-schema`.
6. Si es de infraestructura, `make down` y vuelve a subir; si persiste,
   `./scripts/09_down.sh --volumes` y reconstruye.

## Siguiente paso

[14-troubleshooting.md](14-troubleshooting.md).
