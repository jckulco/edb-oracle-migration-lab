#!/usr/bin/env bash
# =============================================================================
# 07_validate.sh  |  Compara datos y ejecuta pruebas funcionales.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_venv
require_env
wait_for_health oracle 300
wait_for_health edb 300

set +e
run_python -m migration.etl.validate "$@"
status=$?
set -e

if [[ ${status} -eq 0 ]]; then
  log "Validación OK. Reporte: migration/reports/validation.md"
else
  warn "La validación encontró diferencias. Revisa migration/reports/validation.md"
fi
exit "${status}"
