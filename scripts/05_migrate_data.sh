#!/usr/bin/env bash
# =============================================================================
# 05_migrate_data.sh  |  Ejecuta el ETL Oracle -> EPAS.
#
# Por defecto trunca las tablas destino antes de cargar. Pasa --dry-run para
# solo contar filas, o --tables a,b para un subconjunto.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_venv
require_env
wait_for_health oracle 300
wait_for_health edb 300

ARGS=("$@")
if [[ " ${ARGS[*]:-} " != *" --dry-run "* ]]; then
  ARGS+=(--truncate)
fi

run_python -m migration.etl.extract_load "${ARGS[@]}"
