#!/usr/bin/env bash
# =============================================================================
# 04_create_edb_schema.sh  |  Crea las tablas y secuencias en EPAS.
#
# Solo tablas/columnas/restricciones locales. Los índices, FKs, vistas,
# paquetes y triggers se crean DESPUÉS de la carga (06_post_load.sh).
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env
wait_for_health edb 300

log "Reiniciando esquema EPAS (destructivo)..."
edb_file "${ROOT}/sql/edb/00_reset.sql"
edb_file "${ROOT}/sql/edb/01_tables.sql"

log "Tablas creadas. Siguiente paso: make migrate"
