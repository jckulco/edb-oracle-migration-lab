#!/usr/bin/env bash
# =============================================================================
# 01_up.sh  |  Levanta Oracle y EPAS y espera a que estén healthy.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_docker
require_env

log "Construyendo y levantando contenedores..."
compose up -d --build

wait_for_health oracle 600
wait_for_health edb 600

cat <<EOF

  Oracle:  localhost:${ORACLE_PORT:-1521}/${ORACLE_PDB}
           usuario: ${ORACLE_APP_USER}
  EPAS:    localhost:${EDB_PORT:-5444}/${EDB_DB}
           usuario: ${EDB_APP_USER}

  Siguiente paso: make oracle-load
EOF
