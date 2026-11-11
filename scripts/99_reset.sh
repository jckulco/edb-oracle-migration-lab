#!/usr/bin/env bash
# =============================================================================
# 99_reset.sh  |  Reconstruye el laboratorio desde cero.
#
# Elimina contenedores y volúmenes, vuelve a levantar, carga Oracle, crea el
# esquema EPAS, migra y ejecuta el post-carga. No valida automáticamente para
# que puedas revisar los reportes con calma.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

if [[ "${1:-}" != "--yes" ]]; then
  printf 'Esto borrará los datos de Oracle y EPAS. Escribe "RESET" para continuar: '
  read -r confirm
  [[ "${confirm}" == "RESET" ]] || die "Cancelado."
fi

"${SCRIPT_DIR}/09_down.sh" --volumes
"${SCRIPT_DIR}/01_up.sh"
"${SCRIPT_DIR}/02_load_oracle.sh"
"${SCRIPT_DIR}/04_create_edb_schema.sh"
"${SCRIPT_DIR}/05_migrate_data.sh"
"${SCRIPT_DIR}/06_post_load.sh"

log "Laboratorio reconstruido. Ejecuta: make validate"
