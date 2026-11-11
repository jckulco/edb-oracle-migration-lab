# 03. Habilitar Oracle y EDB en Docker

Este documento explica cómo se levantan las dos bases, cómo se autentican, cómo
se conectan y cómo se reinician sin perder datos. Es la parte de infraestructura
del laboratorio.

## Archivos involucrados

| Archivo | Rol |
|---|---|
| `docker/compose.yaml` | Define los servicios `oracle` y `edb`, puertos, volúmenes y healthchecks |
| `docker/oracle/init/01_grants.sh` | Otorga privilegios al usuario de aplicación Oracle en el primer arranque |
| `docker/edb/Dockerfile` | Adapta la imagen oficial de EPAS para ejecutarse sola |
| `docker/edb/entrypoint.sh` | Inicializa el clúster, crea usuarios/base/esquema y arranca EPAS |
| `.env.example` | Plantilla de credenciales, puertos e imágenes |
| `scripts/01_up.sh` | Levanta y espera salud |
| `scripts/09_down.sh` | Detiene; opcionalmente borra volúmenes |

## 1. Oracle Database Free

### Imagen

```dotenv
ORACLE_IMAGE=gvenzl/oracle-free:23-slim
```

La imagen crea una base libre con:

- CDB `FREE`.
- PDB `FREEPDB1`.
- Usuario `SYS`/`SYSTEM` con `ORACLE_PASSWORD`.
- Usuario de aplicación `APP_USER` con `APP_USER_PASSWORD` en `FREEPDB1`.
- Script `healthcheck.sh` para el healthcheck de Docker.

### Variables

```dotenv
ORACLE_PASSWORD=OracleLab_2026
ORACLE_APP_USER=ventas
ORACLE_APP_PASSWORD=VentasLab_2026
ORACLE_PDB=FREEPDB1
ORACLE_PORT=1521
ORACLE_DSN=localhost:1521/FREEPDB1
```

Cambia las contraseñas si el host no es de uso personal.

### Primer arranque e init scripts

La primera vez que se crea el volumen, Oracle tarda varios minutos. Los
archivos de `docker/oracle/init/` se ejecutan **una sola vez**:

- `01_grants.sh` entra como `SYS` al CDB, cambia a `FREEPDB1` y otorga a
  `ventas` los privilegios que `CONNECT`/`RESOURCE` no incluyen:
  `CREATE MATERIALIZED VIEW`, `CREATE DATABASE LINK`, `CREATE JOB`,
  `CREATE SYNONYM`, cuota ilimitada en `USERS`, etc.
- Sin este paso, `07_materialized_views.sql` fallaría con
  `ORA-01031: insufficient privileges`.

Si el volumen ya existía antes de agregar el script, los grants no se
ejecutan. Solución:

```bash
# Opción A: reconstruir el volumen (borra datos)
make down
docker volume rm edb_oracle_lab_oradata
make up

# Opción B: ejecutar los grants manualmente
docker compose --env-file .env -f docker/compose.yaml exec -T oracle \
  bash /container-entrypoint-initdb.d/01_grants.sh
```

### Conectarse con SQL*Plus

Dentro del contenedor:

```bash
docker compose --env-file .env -f docker/compose.yaml exec oracle \
  sqlplus ventas/VentasLab_2026@//localhost:1521/FREEPDB1
```

O usando el target del Makefile:

```bash
make oracle-cli
```

Como `SYS`:

```bash
docker compose --env-file .env -f docker/compose.yaml exec oracle \
  sqlplus sys/OracleLab_2026@//localhost:1521/FREEPDB1 as sysdba
```

Para ejecutar un archivo:

```bash
docker compose --env-file .env -f docker/compose.yaml exec -T oracle \
  sqlplus -S ventas/VentasLab_2026@//localhost:1521/FREEPDB1 \
  < sql/oracle/12_validation_queries.sql
```

### Conectarse con DBeaver / SQL Developer

| Campo | Valor |
|---|---|
| Host | `localhost` |
| Puerto | `1521` |
| Service name | `FREEPDB1` |
| Usuario | `ventas` |
| Contraseña | `VentasLab_2026` |
| Driver | Oracle Thin |

No necesitas Oracle Client para DBeaver: usa el driver JDBC.

## 2. EDB Postgres Advanced Server

### Por qué no basta `image: edb/...`

EPAS no tiene una imagen oficial gratuita en Docker Hub. Las imágenes de EDB
están en un registro privado y están pensadas para Kubernetes/CloudNativePG.
Para el laboratorio se usa una imagen oficial como base y se le añade un
entrypoint que:

1. Ejecuta `initdb` la primera vez.
2. Crea el superusuario `enterprisedb`.
3. Crea el usuario, la base y el esquema de aplicación.
4. Instala `edbspl` (paquetes PL/SQL).
5. Ajusta `search_path`, zona horaria y compatibilidad Redwood.
6. Arranca `edb-postgres` en primer plano.

El resultado es un EPAS **de laboratorio**, no un despliegue productivo.

### Autenticación en el registro

```bash
export EDB_TOKEN='...'
docker login docker.enterprisedb.com --username k8s --password-stdin <<< "$EDB_TOKEN"
```

Si tu organización usa otro registry, autentícate contra él y cambia
`EDB_IMAGE`:

```dotenv
EDB_IMAGE=registry.interna.example.com/edb/epas:16.9
```

### Elegir el tag

El nombre lógico de la imagen es `edb-postgres-advanced`. Los tags suelen
incluir la versión y la base (por ejemplo `16.9-standard-ubi9`). Para listar:

```bash
curl -fsSL -u "k8s:${EDB_TOKEN}" \
  "https://docker.enterprisedb.com/v2/k8s/edb-postgres-advanced/tags/list" \
  | python3 -m json.tool
```

Configura:

```dotenv
EDB_IMAGE=docker.enterprisedb.com/k8s/edb-postgres-advanced:16.9-standard-ubi9
EDB_MAJOR=16
EDB_PLATFORM=linux/amd64
```

- `EDB_MAJOR` debe coincidir con el directorio `/usr/edb/as<N>` de la imagen.
- En Apple Silicon, si la imagen no publica `arm64`, `EDB_PLATFORM` fuerza
  emulación `amd64`. Es más lento, pero funciona.

### Variables de EPAS

```dotenv
EDB_PASSWORD=EdbLab_2026
EDB_APP_USER=ventas
EDB_APP_PASSWORD=VentasLab_2026
EDB_DB=ventas
EDB_PORT=5444
EDB_HOST=localhost
```

`EDB_PASSWORD` es del superusuario `enterprisedb`; `EDB_APP_PASSWORD` es del
usuario `ventas` y del esquema `ventas`.

### Cómo funciona el entrypoint

`docker/edb/entrypoint.sh`:

1. Valida identificadores y contraseñas para evitar inyección en SQL.
2. Si corre como root, crea/chown de `PGDATA` y cede el control al usuario
   `postgres` (uid 26) con `runuser`.
3. Si no existe `PG_VERSION`, ejecuta `initdb -U enterprisedb --encoding=UTF8`.
   EPAS crea `edbspl` en `template1`; además se asegura con
   `CREATE EXTENSION IF NOT EXISTS edbspl`.
4. Ajusta `postgresql.conf` (`port=5444`, `listen_addresses='*'`, UTC).
5. Configura `pg_hba.conf` (trust local, SCRAM por TCP).
6. Arranca una instancia temporal, crea el usuario/base/esquema y aplica:
   - `search_path = ventas, public`
   - `timezone = UTC`
   - `edb_redwood_date = on`
   - `edb_redwood_strings = on`
7. Detiene la instancia temporal y arranca `edb-postgres` en primer plano.

La primera inicialización solo ocurre si el volumen está vacío. Para
repetirla, borra el volumen.

### Conectarse con `edb-psql`

```bash
docker compose --env-file .env -f docker/compose.yaml exec edb \
  edb-psql -U ventas -d ventas
```

`edb-psql` es el cliente de EPAS que entiende bloques `CREATE PACKAGE` sin
los separadores `/` de SQL*Plus. Para scripts con paquetes, usa siempre
`edb-psql`, no un `psql` genérico.

Para ejecutar un archivo:

```bash
docker compose --env-file .env -f docker/compose.yaml exec -T edb \
  edb-psql -X -v ON_ERROR_STOP=1 -U ventas -d ventas \
  -f - < sql/edb/10_validation_queries.sql
```

### Conectarse con DBeaver / psql del host

Si tienes `psql` instalado:

```bash
PGPASSWORD=VentasLab_2026 psql \
  "host=localhost port=5444 dbname=ventas user=ventas sslmode=prefer"
```

DBeaver:

| Campo | Valor |
|---|---|
| Host | `localhost` |
| Puerto | `5444` |
| Base | `ventas` |
| Usuario | `ventas` |
| Driver | PostgreSQL / EDB |
| SSL | Prefer (el laboratorio no configura TLS) |

## 3. Compose: piezas clave

```yaml
services:
  oracle:
    image: ${ORACLE_IMAGE:-gvenzl/oracle-free:23-slim}
    environment:
      ORACLE_PASSWORD: ${ORACLE_PASSWORD:?}
      APP_USER: ${ORACLE_APP_USER:-ventas}
      APP_USER_PASSWORD: ${ORACLE_APP_PASSWORD:?}
    ports:
      - "${ORACLE_PORT:-1521}:1521"
    volumes:
      - oracle_data:/opt/oracle/oradata
      - ./oracle/init:/container-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD", "healthcheck.sh"]

  edb:
    build:
      context: ./edb
      args:
        EDB_IMAGE: ${EDB_IMAGE:?}
        EDB_MAJOR: ${EDB_MAJOR:-16}
    platform: ${EDB_PLATFORM:-linux/amd64}
    ports:
      - "${EDB_PORT:-5444}:5444"
    volumes:
      - edb_data:/var/lib/edb
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -p 5444 -U $${EDB_APP_USER} -d $${EDB_DB}"]
```

Los `${VAR:?mensaje}` hacen que Compose falle con un mensaje claro si falta
una variable obligatoria.

## 4. Operación diaria

```bash
# Levantar / reconstruir
make up
make ps
make logs

# Estado de salud
docker inspect -f '{{.State.Health.Status}}' lab-oracle
docker inspect -f '{{.State.Health.Status}}' lab-edb

# Detener conservando datos
make down

# Detener y borrar datos
./scripts/09_down.sh --volumes

# Reconstruir todo desde cero
make reset
```

### Volúmenes

| Volumen | Contenido | Borrado |
|---|---|---|
| `edb_oracle_lab_oradata` | Datafiles de Oracle | `--volumes` o `docker volume rm` |
| `edb_oracle_lab_epasdata` | `PGDATA` de EPAS | `--volumes` |

Los volúmenes son nombrados y sobreviven a `docker compose down`. `down -v`
los elimina.

### Logs útiles

```bash
docker compose --env-file .env -f docker/compose.yaml logs -f oracle
docker compose --env-file .env -f docker/compose.yaml logs -f edb
docker compose --env-file .env -f docker/compose.yaml exec edb \
  tail -100 /var/log/edb/init.log
```

## 5. Seguridad del laboratorio

- Las contraseñas de `.env.example` son públicas y débiles. Cámbialas.
- No publiques los puertos 1521/5444 a Internet.
- No subas `.env` a Git.
- El laboratorio usa `trust` para conexiones locales dentro del contenedor;
  es aceptable para un entorno aislado, no para producción.
- EPAS se ejecuta como un clúster de un solo nodo, sin TLS, sin backups y sin
  HA. No lo uses para datos reales.
- Si tu imagen de EPAS exige una license key inyectada por el operador de
  Kubernetes, este entrypoint standalone no la configura. Usa una imagen que
  arranque en modo evaluación o consulta a EDB.

## 6. Problemas frecuentes de Docker

| Síntoma | Causa probable | Solución |
|---|---|---|
| `unauthorized: authentication required` | No hiciste `docker login` o el token expiró | Repite el login con `k8s` y el token |
| `manifest unknown` | Tag de EPAS inexistente | Lista tags y actualiza `EDB_IMAGE` |
| `exec format error` | Arquitectura incompatible | Ajusta `EDB_PLATFORM=linux/amd64` |
| `port is already allocated` | Otro proceso usa 1521/5444 | Cambia `ORACLE_PORT`/`EDB_PORT` |
| Oracle unhealthy | Primera inicialización lenta o poca RAM | Espera, revisa logs, sube memoria |
| EPAS reinicia en bucle | `initdb` falló o volumen con permisos | Revisa `init.log`; borra volumen y reintenta |
| `database system is starting up` | Aún no está lista | Espera el healthcheck |
| `permission denied` en volumen | Mezcla de usuarios/root | `./scripts/09_down.sh --volumes` y reconstruye |
| `ORA-01017` | Usuario/contraseña incorrectos | Revisa `.env` y el usuario creado |
| `ORA-12514` | Service name incorrecto | Usa `FREEPDB1` |

Más casos en [14-troubleshooting.md](14-troubleshooting.md).

## 7. Checklist de Docker

- [ ] `.env` creado y con contraseñas cambiadas.
- [ ] `EDB_IMAGE` apunta a un tag existente y autorizado.
- [ ] `docker login` correcto (si aplica).
- [ ] `make check` sin errores.
- [ ] `make up` deja ambos contenedores `healthy`.
- [ ] `make oracle-cli` conecta a `FREEPDB1`.
- [ ] `edb-psql` conecta a `ventas`.
- [ ] Los volúmenes están nombrados y se conservan tras `make down`.
- [ ] Sabes cómo borrar los datos (`./scripts/09_down.sh --volumes`).

## Siguiente paso

[04-modelo-datos.md](04-modelo-datos.md) para entender qué se va a migrar.
