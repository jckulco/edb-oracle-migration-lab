# 14. Troubleshooting

## Diagnóstico rápido

```bash
make ps
make logs
docker compose --env-file .env -f docker/compose.yaml ps
docker inspect -f '{{.State.Health.Status}}' lab-oracle
docker inspect -f '{{.State.Health.Status}}' lab-edb
docker compose --env-file .env -f docker/compose.yaml logs --tail=100 edb
```

## Docker y registro EDB

| Síntoma | Causa | Solución |
|---|---|---|
| `unauthorized: authentication required` | Sin login o token expirado | `docker login docker.enterprisedb.com -u k8s` |
| `manifest unknown` | Tag inexistente | Lista tags y actualiza `EDB_IMAGE` |
| `pull access denied` | Cuenta sin acceso al repo | Verifica suscripción/token |
| `exec format error` | Arquitectura | `EDB_PLATFORM=linux/amd64` |
| `no space left on device` | Disco lleno | `docker system prune`, libera espacio |
| `port is already allocated` | Puerto ocupado | Cambia `ORACLE_PORT`/`EDB_PORT` |
| `Cannot connect to the Docker daemon` | Docker apagado | Inicia Docker |
| `unhealthy` en Oracle | Primera init lenta o RAM | Espera; sube memoria |
| `unhealthy` en EPAS | `initdb` falló | Revisa `/var/log/edb/init.log` |

### Ver el error real de EPAS

```bash
docker compose --env-file .env -f docker/compose.yaml logs edb | tail -100
docker compose --env-file .env -f docker/compose.yaml exec edb \
  sh -c 'cat /var/log/edb/init.log 2>/dev/null | tail -100'
```

Si el contenedor reinicia antes de que puedas entrar:

```bash
docker compose --env-file .env -f docker/compose.yaml run --rm edb bash
```

### Emulación ARM

En Apple Silicon, si EPAS no tiene `arm64`:

```dotenv
EDB_PLATFORM=linux/amd64
```

Es más lento y consume más memoria. Si el contenedor se queda sin memoria,
sube el límite de Docker Desktop.

## Oracle

| Error | Causa | Solución |
|---|---|---|
| `ORA-12541: TNS:no listener` | Oracle aún arranca | Espera healthcheck |
| `ORA-12514: TNS:listener does not currently know of service` | Service name incorrecto | Usa `FREEPDB1` |
| `ORA-01017: invalid username/password` | Credenciales | Revisa `.env` |
| `ORA-01031: insufficient privileges` | Falta grant (MV, synonym) | Ejecuta `01_grants.sh` |
| `ORA-01950: no privileges on tablespace 'USERS'` | Sin cuota | `ALTER USER ... QUOTA UNLIMITED ON USERS` |
| `ORA-00942: table or view does not exist` | Esquema/search_path | Conéctate como `ventas`; revisa el nombre |
| `ORA-00001: unique constraint violated` | Semilla duplicada | Ejecuta `00_reset.sql` y recarga |
| `ORA-04098: trigger is invalid` | Trigger no compiló | `SHOW ERRORS TRIGGER ...` |
| `ORA-12012` / MV | Refresco | Revisa `DBMS_MVIEW` y el estado de la MV |
| `ORA-01536: space quota exceeded` | Cuota | Aumenta cuota |

### Comprobar grants

```sql
SELECT privilege
  FROM user_sys_privs
 WHERE privilege LIKE '%MATERIALIZED%' OR privilege LIKE '%DATABASE LINK%';
```

Si falta:

```bash
docker compose --env-file .env -f docker/compose.yaml exec -T oracle \
  bash /container-entrypoint-initdb.d/01_grants.sh
```

## EPAS: inicialización

| Error | Causa | Solución |
|---|---|---|
| `initdb: could not create directory` | Permisos del volumen | `./scripts/09_down.sh --volumes` y reconstruye |
| `locale "C.UTF-8" not found` | Locale no disponible | El entrypoint reintenta con `C` |
| `database files are incompatible with server` | Volumen de otra versión | Borra volumen |
| `could not bind to port 5444` | Puerto ocupado | Cambia `EDB_PORT` |
| `FATAL: password authentication failed` | Contraseña/rol | Revisa `.env` o recrea |
| `database "ventas" does not exist` | Init incompleto | Revisa logs; borra volumen |
| `role "ventas" does not exist` | Init incompleto | Revisa logs; borra volumen |
| `permission denied for schema ventas` | Dueño incorrecto | Recrea esquema con el usuario correcto |

### Inspeccionar el clúster

```bash
docker compose --env-file .env -f docker/compose.yaml exec edb \
  edb-psql -U enterprisedb -d postgres -c '\l'
```

Si `enterprisedb` no puede autenticarse, usa la conexión local `trust` como
usuario del sistema `postgres`:

```bash
docker compose --env-file .env -f docker/compose.yaml exec -u postgres edb \
  edb-psql -d postgres
```

## EPAS: objetos y paquetes

| Error | Causa | Solución |
|---|---|---|
| `syntax error at or near ";"` | `psql` genérico con paquetes | Usa `edb-psql` |
| `extension "edbspl" does not exist` | Extensión no instalada | `CREATE EXTENSION edbspl;` |
| `function pkg_... does not exist` | Paquete no compilado o `search_path` | Revisa compilación y `search_path` |
| `column ... does not exist` | `%TYPE`/nombre mal | Revisa DDL y esquema |
| `operator does not exist: ...` | Tipo distinto | Revisa mapeo de tipos |
| `invalid input syntax for type json` | JSON inválido | Valida el dato |
| `invalid XML document` | XML mal formado | Valida el XML |
| `cannot execute REFRESH MATERIALIZED VIEW in a transaction block` | `CONCURRENTLY` en transacción | Ejecuta fuera de transacción |
| `ANALYZE cannot be executed from a function` | `pkg_mantenimiento.analizar_tabla` | Ejecuta `ANALYZE` fuera de la función |

### Verificar `edbspl`

```sql
SELECT extname, extversion FROM pg_extension WHERE extname = 'edbspl';
```

Si no está:

```sql
CREATE EXTENSION edbspl;
```

### Verificar paquetes

```sql
SELECT n.nspname, p.proname, p.prokind
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'ventas'
 ORDER BY 1, 2;
```

## Carga de datos

| Error | Causa | Solución |
|---|---|---|
| `connection refused` | Contenedor no listo | `make up`, espera healthy |
| `ORA-12541` | Oracle no listo | Espera |
| `invalid input syntax for type json` | CLOB no es JSON | Revisa el dato |
| `malformed array literal` | Separador | Revisa `normalize_value` |
| `numeric field overflow` | Precisión | Ajusta `numeric(p,s)` |
| `value too long` | `VARCHAR2 BYTE` | Amplía o revisa |
| `duplicate key` | Sin truncate o secuencia | `--truncate` + `setval` |
| `FK violation` | Orden de carga | Respeta `order` |
| `permission denied for table` | Dueño/rol | Conéctate como `ventas` |
| `COPY ...: unexpected EOF` | Proceso interrumpido | Reintenta con `--truncate` |

### Dry run

```bash
make migrate -- --dry-run
```

### Cargar una sola tabla

```bash
make migrate -- --tables regiones
```

Si hay FKs, puede fallar; usa el conjunto completo.

## Validación

| Síntoma | Causa | Solución |
|---|---|---|
| Conteos distintos | Carga incompleta | Revisa `data_load.json` |
| Checksum distinto | Normalización | Revisa tipo y valor en `validation.md` |
| Nulos distintos | Default/trigger | Revisa si el destino generó el valor |
| Prueba funcional falla | Paquete/función distinta | Compara resultados y firma |
| `mv_ventas_mensuales` distinta | MV sin refrescar | `REFRESH MATERIALIZED VIEW` |
| `vw_ventas_mensuales` distinta | Zona horaria/mes | Revisa UTC y `date_trunc` |
| `auditoria` distinta | Trigger durante carga | Crea triggers después de cargar |

### Investigar una fila

```sql
-- Oracle
SELECT * FROM clientes WHERE cliente_id = 3;
-- EPAS
SELECT * FROM ventas.clientes WHERE cliente_id = 3;
```

## Rendimiento

| Síntoma | Causa | Solución |
|---|---|---|
| Todo es Seq Scan | Tablas pequeñas | Normal; prueba con más datos |
| Consulta lenta | Sin índice/estadísticas | `ANALYZE`, revisa plan |
| Índice no usado | Tipo/expresión distinta | Ajusta índice/consulta |
| Bloat | Muchos updates | `VACUUM`, revisa autovacuum |
| COPY lento | Índices/triggers | Carga antes de crearlos |
| Benchmark injusto | Hardware/caché | Mide con datos y entorno equivalentes |

## Errores de red / conexión

```bash
# ¿Está el puerto publicado?
docker compose --env-file .env -f docker/compose.yaml port oracle 1521
docker compose --env-file .env -f docker/compose.yaml port edb 5444

# ¿El contenedor resuelve?
docker compose --env-file .env -f docker/compose.yaml exec edb \
  pg_isready -h 127.0.0.1 -p 5444
```

Si usas WSL2, `localhost` puede no ser el host de Docker; prueba
`host.docker.internal` o la IP de la distro.

## Limpieza total

```bash
make down
./scripts/09_down.sh --volumes
docker system prune -f
make up
```

No ejecutes `docker system prune` si tienes otros proyectos.

## Cuándo pedir ayuda

Incluye:

- Salida de `make check`.
- `docker compose ps`.
- Últimas 100 líneas de logs de Oracle y EPAS.
- Contenido de `.env` **sin contraseñas**.
- `migration/reports/*.json` relevantes.
- Versión de Docker, Python, Oracle y EPAS.

## Siguiente paso

[15-post-migracion.md](15-post-migracion.md).
