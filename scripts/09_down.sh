#!/usr/bin/env bash
# =============================================================================
# 09_down.sh  |  Detiene y elimina los contenedores.
#
#   ./scripts/09_down.sh            # conserva los volúmenes de datos
#   ./scripts/09_down.sh --volumes  # elimina también los datos (destructivo)
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_docker
require_env

if [[ "${1:-}" == "--volumes" ]]; then
  warn "Se eliminarán los volúmenes de Oracle y EPAS. Esta acción no se puede deshacer."
  compose down -v --remove-orphans
else
  compose down --remove-orphans
  log "Volúmenes conservados. Usa --volumes para borrarlos."
fi
