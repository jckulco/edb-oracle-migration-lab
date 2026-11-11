#!/usr/bin/env bash
# =============================================================================
# 13_edbldr.sh  |  Demostración de EDB*Loader (carga masiva)
#
# Carga migration/edb-tools/edbldr/regiones.dat en ventas.regiones_ldr
# dentro del contenedor EPAS, usando el cargador EDB*Loader.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env
wait_for_health edb 300

SRC="${ROOT}/migration/edb-tools/edbldr"
[[ -f "${SRC}/regiones.ctl" && -f "${SRC}/regiones.dat" ]] \
  || die "Faltan los archivos de EDB*Loader en ${SRC}"

log "Creando tabla de staging..."
edb_file "${ROOT}/sql/edb/12_edbldr_staging.sql"

CID="$(compose ps -q edb)"
[[ -n "${CID}" ]] || die "No se encontró el contenedor de EPAS"
docker exec "${CID}" mkdir -p /tmp/edbldr
docker cp "${SRC}/regiones.ctl" "${CID}:/tmp/edbldr/regiones.ctl"
docker cp "${SRC}/regiones.dat" "${CID}:/tmp/edbldr/regiones.dat"

log "Ejecutando EDB*Loader..."
compose exec -T edb bash -c "
  cd /tmp/edbldr &&
  PGCLIENTENCODING=UTF8 edbldr \
    -d '${EDB_DB}' -p 5444 -h 127.0.0.1 \
    USERID='${EDB_APP_USER}/${EDB_APP_PASSWORD}' \
    CONTROL=regiones.ctl DATA=regiones.dat \
    BAD=regiones.bad DISCARD=regiones.dsc LOG=regiones.log
"

log "Verificando carga..."
COUNT="$(edb_scalar "SELECT COUNT(*) FROM ventas.regiones_ldr")"
[[ "${COUNT}" == "4" ]] \
  || die "Se esperaban 4 filas en regiones_ldr y hay ${COUNT}. Revisa /tmp/edbldr/regiones.bad y regiones.log"

edb_sql "SELECT region_id, nombre, codigo FROM ventas.regiones_ldr ORDER BY region_id;"
log "EDB*Loader OK: 4 filas en ventas.regiones_ldr."
