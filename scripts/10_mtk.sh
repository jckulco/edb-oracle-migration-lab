#!/usr/bin/env bash
# =============================================================================
# 10_mtk.sh  |  Integración con EDB Migration Toolkit (MTK)
#
# MTK es una herramienta comercial de línea de comandos. Este wrapper:
#   * valida que runMTK.sh y toolkit.properties existan;
#   * puede generar/actualizar toolkit.properties desde .env;
#   * ejecuta modos offline (seguros, no tocan el destino);
#   * deja los artefactos en migration/reports/mtk/.
#
# Uso:
#   ./scripts/10_mtk.sh offline-schema
#   ./scripts/10_mtk.sh offline-data
#   ./scripts/10_mtk.sh offline-full
#   ./scripts/10_mtk.sh online-schema --write-properties
#   ./scripts/10_mtk.sh online-data
#
# Variables:
#   MTK_HOME          /usr/edb/migrationtoolkit
#   MTK_BIN           $MTK_HOME/bin/runMTK.sh
#   MTK_PROPERTIES    $MTK_HOME/etc/toolkit.properties
#   MTK_OUT_DIR       migration/reports/mtk
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env
command -v java >/dev/null 2>&1 || warn "Java no está en PATH; MTK podría usar su propio JRE."

MODE="${1:-offline-schema}"
WRITE_PROPERTIES="${2:-}"

MTK_HOME="${MTK_HOME:-/usr/edb/migrationtoolkit}"
MTK_BIN="${MTK_BIN:-${MTK_HOME}/bin/runMTK.sh}"
MTK_PROPERTIES="${MTK_PROPERTIES:-${MTK_HOME}/etc/toolkit.properties}"
OUT="${MTK_OUT_DIR:-${ROOT}/migration/reports/mtk}"
mkdir -p "${OUT}/logs"

if [[ ! -x "${MTK_BIN}" ]]; then
  warn "No se encontró runMTK.sh en ${MTK_BIN}."
  warn "Instala EDB Migration Toolkit y define MTK_HOME o MTK_BIN."
  warn "Documentación: migration/edb-tools/mtk/README.md"
  exit 3
fi

generate_properties() {
  local backup=""
  if [[ -f "${MTK_PROPERTIES}" ]]; then
    backup="${MTK_PROPERTIES}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "${MTK_PROPERTIES}" "${backup}"
    log "Respaldo de toolkit.properties: ${backup}"
  fi
  install -d -m 700 "$(dirname "${MTK_PROPERTIES}")"
  umask 077
  cat > "${MTK_PROPERTIES}" <<EOF
# Generado por scripts/10_mtk.sh el $(date -Iseconds)
SRC_DB_URL=jdbc:oracle:thin:@//localhost:${ORACLE_PORT:-1521}/${ORACLE_PDB}
SRC_DB_USER=${ORACLE_APP_USER}
SRC_DB_PASSWORD=${ORACLE_APP_PASSWORD}

TARGET_DB_URL=jdbc:edb://localhost:${EDB_PORT:-5444}/${EDB_DB}
TARGET_DB_USER=${EDB_APP_USER}
TARGET_DB_PASSWORD=${EDB_APP_PASSWORD}
EOF
  chmod 600 "${MTK_PROPERTIES}"
  log "toolkit.properties actualizado: ${MTK_PROPERTIES}"
}

if [[ "${WRITE_PROPERTIES}" == "--write-properties" ]]; then
  generate_properties
fi

if [[ ! -r "${MTK_PROPERTIES}" ]]; then
  warn "No existe o no es legible ${MTK_PROPERTIES}."
  warn "Copia migration/edb-tools/mtk/toolkit.properties.example y ajústalo,"
  warn "o ejecuta este script con --write-properties (sobrescribe el archivo)."
  exit 3
fi

if ! grep -q '^SRC_DB_URL=' "${MTK_PROPERTIES}"; then
  die "${MTK_PROPERTIES} no contiene SRC_DB_URL; revisa el formato."
fi

SCHEMA_SCOPE="${MTK_SCHEMA:-VENTAS}"
COMMON_OPTS=(
  -offlineMigration
  -schemaOnly
  -allTables
  -indexes
  -constraints
  -triggers
  -allViews
  -allSequences
  -allProcs
  -allFuncs
  -allPackages
  -objectTypes
  -logDir "${OUT}/logs"
  -verbose on
)

run_offline() {
  local label="$1"; shift
  log "MTK ${label} (offline, no escribe en EPAS)..."
  (
    cd "${OUT}"
    "${MTK_BIN}" "$@" "${SCHEMA_SCOPE}" 2>&1 | tee "${OUT}/mtk_${label}.log"
  )
}

case "${MODE}" in
  offline-schema)
    run_offline schema "${COMMON_OPTS[@]}"
    ;;
  offline-data)
    run_offline data -offlineMigration -dataOnly -singleDataFile -safeMode \
      -logDir "${OUT}/logs" -verbose on
    ;;
  offline-full)
    run_offline full -offlineMigration \
      -logDir "${OUT}/logs" -verbose on
    ;;
  online-schema)
    [[ "${MTK_ALLOW_ONLINE:-0}" == "1" ]] \
      || die "Modo online deshabilitado. Exporta MTK_ALLOW_ONLINE=1 si aceptas crear/borrar ventas_mtk."
    warn "El modo online escribe en el esquema ventas_mtk, no en ventas."
    (
      cd "${OUT}"
      "${MTK_BIN}" -schemaOnly -targetSchema ventas_mtk -dropSchema true \
        -logDir "${OUT}/logs" -verbose on "${SCHEMA_SCOPE}" \
        2>&1 | tee "${OUT}/mtk_online_schema.log"
    )
    ;;
  online-data)
    [[ "${MTK_ALLOW_ONLINE:-0}" == "1" ]] \
      || die "Modo online deshabilitado. Exporta MTK_ALLOW_ONLINE=1 si aceptas escribir en ventas_mtk."
    (
      cd "${OUT}"
      "${MTK_BIN}" -dataOnly -targetSchema ventas_mtk \
        -logDir "${OUT}/logs" -verbose on "${SCHEMA_SCOPE}" \
        2>&1 | tee "${OUT}/mtk_online_data.log"
    )
    ;;
  *)
    die "Modo MTK desconocido: ${MODE}. Usa offline-schema|offline-data|offline-full|online-schema|online-data"
    ;;
esac

log "Artefactos MTK en: ${OUT}"
find "${OUT}" -maxdepth 1 -type f -printf '  %f\n' | sort
