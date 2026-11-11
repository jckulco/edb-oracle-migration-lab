#!/usr/bin/env bash
# =============================================================================
# Utilidades compartidas por los scripts del laboratorio.
# No ejecutar directamente: se carga con `source`.
# =============================================================================
set -o pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${COMMON_DIR}/../.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
COMPOSE_FILE="${ROOT_DIR}/docker/compose.yaml"
PYTHON="${PYTHON:-${ROOT_DIR}/.venv/bin/python}"

log()  { printf '\033[1;34m[lab]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[lab:warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[lab:error]\033[0m %s\n' "$*" >&2; exit 1; }

compose() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Falta el comando '$1'. Instálalo y reintenta."
}

require_env() {
  [[ -f "${ENV_FILE}" ]] || die "No existe ${ENV_FILE}. Ejecuta: cp .env.example .env"
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
  : "${ORACLE_PASSWORD:?Falta ORACLE_PASSWORD en .env}"
  : "${ORACLE_APP_USER:?Falta ORACLE_APP_USER en .env}"
  : "${ORACLE_APP_PASSWORD:?Falta ORACLE_APP_PASSWORD en .env}"
  : "${ORACLE_PDB:?Falta ORACLE_PDB en .env}"
  : "${EDB_IMAGE:?Falta EDB_IMAGE en .env (requiere acceso al registro de EDB)}"
  : "${EDB_APP_USER:?Falta EDB_APP_USER en .env}"
  : "${EDB_APP_PASSWORD:?Falta EDB_APP_PASSWORD en .env}"
  : "${EDB_DB:?Falta EDB_DB en .env}"
}

require_docker() {
  require_cmd docker
  docker compose version >/dev/null 2>&1 \
    || die "Docker Compose v2 no está disponible (docker compose version)."
  docker info >/dev/null 2>&1 \
    || die "El daemon de Docker no responde. Inicia Docker Desktop/Engine."
}

require_venv() {
  [[ -x "${PYTHON}" ]] || die "No existe ${PYTHON}. Ejecuta: make venv"
}

run_python() {
  require_venv
  ( cd "${ROOT_DIR}" && PYTHONPATH="${ROOT_DIR}" "${PYTHON}" "$@" )
}

wait_for_health() {
  local service="$1"
  local timeout="${2:-300}"
  local cid status
  cid="$(compose ps -q "${service}")"
  [[ -n "${cid}" ]] || die "El servicio ${service} no está creado. Ejecuta: make up"

  log "Esperando a que ${service} esté healthy (máx. ${timeout}s)..."
  for _ in $(seq 1 "${timeout}"); do
    status="$(docker inspect -f \
      '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      "${cid}" 2>/dev/null || echo missing)"
    case "${status}" in
      healthy) log "${service} healthy."; return 0 ;;
      exited|dead) die "${service} terminó en estado ${status}. Revisa: docker compose logs ${service}" ;;
    esac
    sleep 1
  done
  die "Timeout esperando a ${service}. Revisa: make logs"
}

oracle_conn() {
  printf '%s/%s@//localhost:1521/%s' \
    "${ORACLE_APP_USER}" "${ORACLE_APP_PASSWORD}" "${ORACLE_PDB}"
}

# Ejecuta un archivo .sql en Oracle como usuario de aplicación.
oracle_file() {
  local file="$1"
  [[ -f "${file}" ]] || die "No existe el archivo Oracle: ${file}"
  log "Oracle <- $(basename "${file}")"
  {
    printf 'WHENEVER SQLERROR EXIT SQL.SQLCODE\n'
    printf 'SET DEFINE OFF\n'
    cat "${file}"
    printf '\nEXIT\n'
  } | compose exec -T oracle sqlplus -S -L "$(oracle_conn)"
}

# Ejecuta un archivo .sql en EPAS con edb-psql (parser de paquetes EDB).
edb_file() {
  local file="$1"
  [[ -f "${file}" ]] || die "No existe el archivo EPAS: ${file}"
  log "EPAS <- $(basename "${file}")"
  compose exec -T edb edb-psql \
    -X -v ON_ERROR_STOP=1 \
    -U "${EDB_APP_USER}" -d "${EDB_DB}" \
    -f - < "${file}"
}

edb_sql() {
  printf '%s\n' "$1" | compose exec -T edb edb-psql \
    -X -v ON_ERROR_STOP=1 -U "${EDB_APP_USER}" -d "${EDB_DB}" -f -
}

edb_scalar() {
  local sql="$1"
  printf '\\pset tuples_only on\n\\pset format unaligned\n%s;\n' "${sql}" \
    | compose exec -T edb edb-psql -X -v ON_ERROR_STOP=1 \
        -U "${EDB_APP_USER}" -d "${EDB_DB}" -f - \
    | tr -d '[:space:]'
}
