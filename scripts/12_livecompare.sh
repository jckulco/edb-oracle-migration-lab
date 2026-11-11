#!/usr/bin/env bash
# =============================================================================
# 12_livecompare.sh  |  Compara Oracle vs EPAS con EDB LiveCompare
#
# LiveCompare 4.x compara Oracle (python-oracledb thin) contra PostgreSQL/EPAS.
# Requiere:
#   * binario `livecompare` en PATH o LIVECOMPARE_BIN;
#   * base de datos de salida (por defecto `livecompare`) en EPAS;
#   * grants Oracle: CONNECT, SELECT ANY TABLE, SELECT_CATALOG_ROLE.
#
# Uso:
#   ./scripts/12_livecompare.sh --grant   # otorga grants y ejecuta
#   ./scripts/12_livecompare.sh --dry-run # valida configuración
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env
wait_for_health oracle 300
wait_for_health edb 300
require_venv

LIVECOMPARE_BIN="${LIVECOMPARE_BIN:-livecompare}"
command -v "${LIVECOMPARE_BIN}" >/dev/null 2>&1 || {
  warn "No se encontró el binario '${LIVECOMPARE_BIN}'."
  warn "Instala EDB LiveCompare y define LIVECOMPARE_BIN si está en otra ruta."
  warn "Documentación: migration/edb-tools/livecompare/README.md"
  exit 3
}

GRANT=0
DRY_RUN=0
for arg in "$@"; do
  case "${arg}" in
    --grant) GRANT=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) die "Argumento desconocido: ${arg}" ;;
  esac
done

if [[ "${GRANT}" -eq 1 ]]; then
  warn "Otorgando a ${ORACLE_APP_USER}: CONNECT, SELECT ANY TABLE, SELECT_CATALOG_ROLE."
  warn "Son privilegios amplios; acéptalos solo en el laboratorio."
  oracle_sys_sql "GRANT CONNECT, SELECT ANY TABLE, SELECT_CATALOG_ROLE TO ${ORACLE_APP_USER};"
fi

OUT="${LIVECOMPARE_OUT_DIR:-${ROOT}/migration/reports/livecompare}"
mkdir -p "${OUT}"
chmod 700 "${OUT}"

LIVE_DB="${EDB_LIVECOMPARE_DB:-livecompare}"
[[ "${LIVE_DB}" =~ ^[a-z_][a-z0-9_]*$ ]] || die "EDB_LIVECOMPARE_DB inválido: ${LIVE_DB}"

if [[ "$(edb_super_scalar "SELECT 1 FROM pg_database WHERE datname = '${LIVE_DB}'")" != "1" ]]; then
  log "Creando base de salida ${LIVE_DB}..."
  edb_super_sql "CREATE DATABASE ${LIVE_DB} OWNER ${EDB_APP_USER};"
fi

INI="${OUT}/livecompare.ini"
umask 077
TABLES="$(run_python - <<'PY'
from migration.etl.config import load_manifest
print(",".join(f"'{t.name}'" for t in load_manifest().tables))
PY
)"

cat > "${INI}" <<EOF
; Generado por scripts/12_livecompare.sh el $(date -Iseconds)
; No versionar: contiene credenciales.
[General Settings]
logical_replication_mode = off
max_parallel_workers = 2
oracle_user_tables_only = on
oracle_ignore_unsortable = on
column_intersection = on
difference_tie_breakers = oracle
schema_qualified_table_names = off

[Oracle Connection]
technology = oracle
host = localhost
port = ${ORACLE_PORT:-1521}
service = ${ORACLE_PDB}
user = ${ORACLE_APP_USER}
password = ${ORACLE_APP_PASSWORD}

[EDB Connection]
technology = postgresql
dsn = host=localhost port=${EDB_PORT:-5444} dbname=${EDB_DB} user=${EDB_APP_USER} password=${EDB_APP_PASSWORD}
start_query = SET search_path = ${EDB_APP_USER}, public

[Output Connection]
dsn = host=localhost port=${EDB_PORT:-5444} dbname=${LIVE_DB} user=${EDB_APP_USER} password=${EDB_APP_PASSWORD}

[Table Filter]
tables = table_name in (${TABLES})
EOF
chmod 600 "${INI}"

log "Configuración: ${INI}"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  ( cd "${OUT}" && "${LIVECOMPARE_BIN}" "${INI}" --dry-run )
  log "Dry-run completado."
  exit 0
fi

log "Ejecutando LiveCompare (puede tardar)..."
( cd "${OUT}" && "${LIVECOMPARE_BIN}" "${INI}" ) | tee "${OUT}/livecompare.log"

log "Resultados en ${OUT}/lc_session_*"
log "Consulta resumen:"
log "  SELECT * FROM livecompare.vw_table_summary ORDER BY session_id DESC LIMIT 5;"
