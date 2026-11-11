# 02. Requisitos

## Hardware recomendado

| Recurso | Mínimo | Recomendado |
|---|---|---|
| CPU | 4 vCPU | 8 vCPU |
| RAM | 8 GB | 16 GB |
| Disco libre | 20 GB | 40 GB SSD |
| Arquitectura | amd64 | amd64; arm64 solo si ambas imágenes la soportan |

Oracle Free y EPAS consumen memoria. Si Docker Desktop tiene menos de 8 GB,
los contenedores pueden reiniciarse por OOM.

## Software

| Herramienta | Versión | Notas |
|---|---|---|
| Docker Engine / Desktop | 24+ | Con Compose v2 (`docker compose`) |
| Python | 3.11+ | 3.12 recomendado; en Debian/Ubuntu instala `python3-venv` |
| Git | 2.30+ | Para clonar y versionar |
| Make | GNU Make 4+ | Opcional pero recomendado |
| Cliente Oracle | No obligatorio | `python-oracledb` thin evita Instant Client |
| Cliente EPAS | No obligatorio | Se usa `psql` dentro del contenedor |

En Windows se recomienda WSL2 con Docker Desktop y el repositorio dentro del
filesystem de Linux (`~/proyectos`, no `/mnt/c`) para evitar problemas de
permisos y rendimiento.

## Acceso a EDB

EPAS es comercial. Para construir el contenedor necesitas una de estas vías:

1. **Registro de EDB (recomendado)**: una cuenta EDB y un token de acceso a
   repositorios. El registro unificado es `docker.enterprisedb.com`.
2. **Imagen corporativa**: tu organización ya tiene una imagen de EPAS en un
   registry interno. Usa esa referencia en `EDB_IMAGE`.
3. **EPAS instalado en un host**: fuera del alcance de Compose, pero el ETL
   puede apuntar a ese host cambiando `EDB_HOST`, `EDB_PORT`, etc.

No hay una imagen pública gratuita de EPAS en Docker Hub. Las imágenes de
Quay.io de EDB están deprecadas y pensadas para CloudNativePG; no son la ruta
recomendada.

### Obtener el token

1. Inicia sesión en <https://www.enterprisedb.com/repos-downloads>.
2. Genera un token de repositorio.
3. Guarda el token en una variable de entorno, nunca en Git:

```bash
export EDB_TOKEN='...'
docker login docker.enterprisedb.com --username k8s --password-stdin <<< "$EDB_TOKEN"
```

El usuario del registro es `k8s` según la documentación de EDB. Si tu
organización usa otro usuario, ajústalo.

### Descubrir un tag válido

```bash
curl -fsSL -u "k8s:${EDB_TOKEN}" \
  "https://docker.enterprisedb.com/v2/k8s/edb-postgres-advanced/tags/list" \
  | python3 -m json.tool | head -50
```

Elige un tag de la rama 16.x, por ejemplo `16.9-standard-ubi9`, y colócalo en
`.env`:

```dotenv
EDB_IMAGE=docker.enterprisedb.com/k8s/edb-postgres-advanced:16.9-standard-ubi9
```

Si el tag no existe, el error será `manifest unknown`. No es un problema del
laboratorio: el catálogo de tags cambia con las versiones de EDB.

## Oracle Database Free

- Imagen `gvenzl/oracle-free:23-slim` (multiarquitectura desde 23.5).
- Límites de la edición Free: 12 GB de datos de usuario, 2 GB de RAM y 2 CPU
  (los límites son de licencia, no solo técnicos).
- PDB por defecto: `FREEPDB1`.
- El usuario de aplicación se crea con `APP_USER` y `APP_USER_PASSWORD`.
- El script `docker/oracle/init/01_grants.sh` agrega privilegios para vistas
  materializadas y otros objetos.

## Puertos

Si `1521` o `5444` están ocupados, cámbialos en `.env`:

```dotenv
ORACLE_PORT=1522
EDB_PORT=5445
```

Recuerda actualizar `ORACLE_DSN` y las variables del ETL si cambias el puerto
de Oracle.

## Primer arranque

```bash
git clone <URL_DEL_REPOSITORIO> edb-oracle-migration-lab
cd edb-oracle-migration-lab

cp .env.example .env
# Edita .env: contraseñas, EDB_IMAGE y, si aplica, puertos.

make venv
make check

# Autenticación en el registro de EDB (solo si usas la imagen oficial)
docker login docker.enterprisedb.com --username k8s

make up
```

`make up` construye la imagen de EPAS y espera a que ambos contenedores estén
`healthy`. La primera vez puede tardar varios minutos: Oracle inicializa una
base de datos y EPAS ejecuta `initdb`.

## Variables de entorno

| Variable | Obligatoria | Descripción |
|---|---|---|
| `ORACLE_PASSWORD` | Sí | SYS/SYSTEM en Oracle |
| `ORACLE_APP_USER` | Sí | Usuario de aplicación; por defecto `ventas` |
| `ORACLE_APP_PASSWORD` | Sí | Contraseña del usuario de aplicación |
| `ORACLE_PDB` | Sí | PDB; por defecto `FREEPDB1` |
| `ORACLE_DSN` | Sí | DSN del ETL, por ejemplo `localhost:1521/FREEPDB1` |
| `EDB_IMAGE` | Sí | Imagen EPAS autorizada |
| `EDB_MAJOR` | No | 16 por defecto; debe coincidir con la ruta de la imagen |
| `EDB_PLATFORM` | No | `linux/amd64` por defecto |
| `EDB_OS_USER` | No | Usuario del sistema en la imagen; `postgres` por defecto |
| `EDB_PASSWORD` | Sí | Superusuario `enterprisedb` |
| `EDB_APP_USER` | Sí | Usuario/esquema de aplicación |
| `EDB_APP_PASSWORD` | Sí | Contraseña del usuario |
| `EDB_DB` | Sí | Base de datos destino |
| `EDB_HOST` / `EDB_PORT` | Sí | Conexión del ETL |
| `ETL_BATCH_SIZE` | No | Filas por fetch; 1000 por defecto |

## Verificación rápida

```bash
docker compose --env-file .env -f docker/compose.yaml ps
docker compose --env-file .env -f docker/compose.yaml logs --tail=50 edb
```

Debes ver `lab-oracle` y `lab-edb` en estado `healthy` y la línea
`database system is ready to accept connections` en EPAS.

## Siguiente paso

[03-docker-oracle-edb.md](03-docker-oracle-edb.md): habilitar, conectar y
operar ambas bases en Docker.
