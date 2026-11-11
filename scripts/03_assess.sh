#!/usr/bin/env bash
# =============================================================================
# 03_assess.sh  |  Genera el assessment del esquema Oracle.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_venv
require_env
wait_for_health oracle 300

run_python -m migration.etl.assess "$@"
log "Reporte: migration/reports/assessment.md"
