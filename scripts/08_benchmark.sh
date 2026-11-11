#!/usr/bin/env bash
# =============================================================================
# 08_benchmark.sh  |  Compara tiempos de consultas equivalentes.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_venv
require_env
wait_for_health oracle 300
wait_for_health edb 300

run_python -m migration.etl.benchmark "$@"
log "Reporte: migration/reports/benchmark.md"
