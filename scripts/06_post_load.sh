#!/usr/bin/env bash
# =============================================================================
# 06_post_load.sh  |  Crea índices, FKs, vistas, MV, paquetes y triggers.
#
# El orden importa:
#   índices/FKs -> vistas -> MV -> paquetes -> triggers -> resync/refresh
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env
wait_for_health edb 300

FILES=(
  02_indexes.sql
  03_constraints.sql
  04_views.sql
  05_materialized_views.sql
  06_packages.sql
  07_standalone.sql
  08_triggers.sql
  09_after_load.sql
)

for file in "${FILES[@]}"; do
  edb_file "${ROOT}/sql/edb/${file}"
done

log "Post-carga completado. Siguiente paso: make validate"
