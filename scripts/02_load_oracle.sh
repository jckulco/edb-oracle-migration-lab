#!/usr/bin/env bash
# =============================================================================
# 02_load_oracle.sh  |  Crea el esquema VENTAS en Oracle y carga los datos.
#
# Es destructivo: 00_reset.sql elimina los objetos del usuario VENTAS.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env
wait_for_health oracle 300

log "Asegurando privilegios del usuario de aplicación..."
compose exec -T oracle bash /container-entrypoint-initdb.d/01_grants.sh

FILES=(
  00_reset.sql
  01_types.sql
  02_tables.sql
  03_sequences.sql
  04_indexes.sql
  05_constraints.sql
  06_views.sql
  07_materialized_views.sql
  08_packages.sql
  09_standalone.sql
  10_triggers.sql
  11_seed.sql
)

for file in "${FILES[@]}"; do
  oracle_file "${ROOT}/sql/oracle/${file}"
done

log "Esquema Oracle cargado. Inspecciona con: make oracle-cli"
oracle_file "${ROOT}/sql/oracle/12_validation_queries.sql"
