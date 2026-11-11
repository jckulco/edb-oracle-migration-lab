#!/usr/bin/env bash
# =============================================================================
# Entrypoint standalone para EPAS (adaptado de las imágenes de CloudNativePG).
#
# Responsabilidades:
#   1. Ejecutarse como root y ceder el control al usuario postgres (uid 26).
#   2. Inicializar el clúster con initdb la primera vez (incluye edbspl).
#   3. Crear el superusuario enterprisedb, el usuario de app, la base y el
#      esquema de aplicación.
#   4. Ajustar compatibilidad Redwood y search_path.
#   5. Arrancar edb-postgres en primer plano.
#
# Variables: EDB_PASSWORD, EDB_APP_USER, EDB_APP_PASSWORD, EDB_DB, EDB_PORT,
#            EDB_HOME, PGDATA.
# =============================================================================
set -Eeuo pipefail

: "${EDB_PASSWORD:?EDB_PASSWORD no está definido}"
: "${EDB_APP_PASSWORD:?EDB_APP_PASSWORD no está definido}"

EDB_APP_USER="${EDB_APP_USER:-ventas}"
EDB_DB="${EDB_DB:-ventas}"
EDB_PORT="${EDB_PORT:-5444}"
EDB_HOME="${EDB_HOME:-/usr/edb/as16}"
PGBIN="${PGBIN:-${EDB_HOME}/bin}"
PGDATA="${PGDATA:-/var/lib/edb/as16/data}"
EDB_OS_USER="${EDB_OS_USER:-postgres}"

log() { printf '[edb-init] %s\n' "$*"; }
die() { printf '[edb-init] ERROR: %s\n' "$*" >&2; exit 1; }

# Los identificadores se interpolan en SQL: validarlos es obligatorio.
[[ "$EDB_APP_USER" =~ ^[a-z_][a-z0-9_]*$ ]] || die "EDB_APP_USER inválido: $EDB_APP_USER"
[[ "$EDB_DB"       =~ ^[a-z_][a-z0-9_]*$ ]] || die "EDB_DB inválido: $EDB_DB"
[[ "$EDB_APP_USER" != "enterprisedb" ]] || die "EDB_APP_USER no puede ser enterprisedb"

sql_literal() { printf "%s" "$1" | sed "s/'/''/g"; }

# ---------------------------------------------------------------------------
# Fase 1: root -> postgres
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -eq 0 ]]; then
  id "${EDB_OS_USER}" >/dev/null 2>&1 \
    || die "El usuario del sistema ${EDB_OS_USER} no existe en la imagen"
  pg_uid="$(id -u "${EDB_OS_USER}")"
  pg_gid="$(id -g "${EDB_OS_USER}")"
  mkdir -p "$PGDATA" "$(dirname "$PGDATA")" /var/log/edb
  chown -R "${pg_uid}:${pg_gid}" "$PGDATA" "$(dirname "$PGDATA")" /var/log/edb
  chmod 700 "$PGDATA"
  exec runuser -u "${EDB_OS_USER}" --preserve-environment -- "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Fase 2: usuario del sistema operativo (postgres por defecto)
# ---------------------------------------------------------------------------
[[ "$(id -un)" == "${EDB_OS_USER}" ]] || die "El entrypoint debe correr como ${EDB_OS_USER}"
[[ -x "${PGBIN}/initdb" ]] || die "No se encontró ${PGBIN}/initdb"
[[ -x "${PGBIN}/postgres" ]] || die "No se encontró ${PGBIN}/postgres"

if [[ ! -s "${PGDATA}/PG_VERSION" ]]; then
  log "Inicializando clúster EPAS en ${PGDATA}..."

  initdb_args=(
    -D "$PGDATA"
    -U enterprisedb
    --encoding=UTF8
    --auth-local=trust
    --auth-host=scram-sha-256
  )
  # C.UTF-8 existe en UBI; si no, se usa el locale C.
  if ! "${PGBIN}/initdb" "${initdb_args[@]}" --locale=C.UTF-8 >/tmp/initdb.log 2>&1; then
    log "Locale C.UTF-8 no disponible; reintentando con locale C."
    find "${PGDATA:?}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    "${PGBIN}/initdb" "${initdb_args[@]}" --locale=C >/tmp/initdb.log 2>&1 \
      || { cat /tmp/initdb.log >&2; die "initdb falló"; }
  fi

  cat >> "${PGDATA}/postgresql.conf" <<EOF

# ---- Laboratorio Oracle -> EPAS ----
port = ${EDB_PORT}
listen_addresses = '*'
max_connections = 200
shared_buffers = 256MB
timezone = 'UTC'
log_timezone = 'UTC'
password_encryption = 'scram-sha-256'
log_min_duration_statement = 500
EOF

  cat > "${PGDATA}/pg_hba.conf" <<'EOF'
# Laboratorio: trust local, SCRAM por TCP.
local   all all trust
host    all all 127.0.0.1/32 scram-sha-256
host    all all ::1/128      scram-sha-256
host    all all 0.0.0.0/0    scram-sha-256
host    all all ::/0         scram-sha-256
EOF

  cleanup_on_error() {
    "${PGBIN}/pg_ctl" -D "$PGDATA" -m immediate -w stop >/dev/null 2>&1 || true
  }
  trap cleanup_on_error ERR

  log "Arrancando instancia temporal para crear usuarios..."
  "${PGBIN}/pg_ctl" -D "$PGDATA" -l /var/log/edb/init.log -o "-p ${EDB_PORT}" -w start

  "${PGBIN}/psql" -p "$EDB_PORT" -U enterprisedb -d postgres -v ON_ERROR_STOP=1 \
    -c "ALTER USER enterprisedb PASSWORD '$(sql_literal "$EDB_PASSWORD")';"

  "${PGBIN}/psql" -p "$EDB_PORT" -U enterprisedb -d postgres -v ON_ERROR_STOP=1 \
    -c "CREATE USER ${EDB_APP_USER} PASSWORD '$(sql_literal "$EDB_APP_PASSWORD")';"

  "${PGBIN}/psql" -p "$EDB_PORT" -U enterprisedb -d postgres -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE ${EDB_DB} OWNER ${EDB_APP_USER};"

  "${PGBIN}/psql" -p "$EDB_PORT" -U enterprisedb -d "$EDB_DB" -v ON_ERROR_STOP=1 <<EOF
CREATE SCHEMA IF NOT EXISTS ${EDB_APP_USER} AUTHORIZATION ${EDB_APP_USER};
CREATE EXTENSION IF NOT EXISTS edbspl;
ALTER DATABASE ${EDB_DB} SET search_path TO ${EDB_APP_USER}, public;
ALTER DATABASE ${EDB_DB} SET timezone TO 'UTC';
ALTER DATABASE ${EDB_DB} SET edb_redwood_date TO on;
ALTER DATABASE ${EDB_DB} SET edb_redwood_strings TO on;
EOF

  trap - ERR
  log "Deteniendo instancia temporal..."
  "${PGBIN}/pg_ctl" -D "$PGDATA" -m fast -w stop
  log "Clúster inicializado."
fi

log "Arrancando EPAS en el puerto ${EDB_PORT} (base ${EDB_DB})..."
exec "${PGBIN}/postgres" -D "$PGDATA" -p "$EDB_PORT"
