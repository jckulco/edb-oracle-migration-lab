#!/usr/bin/env bash
# =============================================================================
# 11_portal_export.sh  |  Exporta DDL Oracle para EDB Migration Portal
#
# Genera:
#   migration/reports/portal/ventas_ddl.sql
#   migration/reports/portal/ventas_ddl.zip
#   migration/reports/portal/README.md
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env
wait_for_health oracle 300

OUT="${PORTAL_OUT_DIR:-${ROOT}/migration/reports/portal}"
mkdir -p "${OUT}"

log "Generando DDL con DBMS_METADATA..."
oracle_file "${ROOT}/sql/oracle/13_export_portal_ddl.sql"

CID="$(compose ps -q oracle)"
[[ -n "${CID}" ]] || die "No se encontró el contenedor de Oracle"
docker cp "${CID}:/tmp/ventas_ddl.sql" "${OUT}/ventas_ddl.sql"

cat > "${OUT}/README.md" <<EOF
# DDL para EDB Migration Portal

Generado: $(date -Iseconds)

## Cómo usarlo

1. Abre <https://migration.enterprisedb.com/> e inicia sesión.
2. Crea un proyecto nuevo.
3. Sube \`ventas_ddl.sql\` (o el ZIP).
4. Selecciona **Create & assess**.
5. Revisa los objetos que no estén al 100 % y usa el AI Copilot o la
   Knowledge Base para resolverlos.
6. Descarga el DDL compatible y contrástalo con \`sql/edb/\` antes de
   aplicarlo.

## Qué contiene

DDL de tipos, secuencias, tablas, constraints, índices, vistas, vistas
materializadas, paquetes, procedimientos, funciones y triggers del esquema
\`VENTAS\`.

## Limitaciones

- Migration Portal analiza el esquema, no los datos.
- Las correcciones automáticas y las sugerencias del Copilot deben probarse.
- La validación de datos se hace con este laboratorio (\`make validate\`) o con
  LiveCompare.
EOF

python3 - "${OUT}" <<'PY'
import sys
import zipfile
from pathlib import Path

out = Path(sys.argv[1])
with zipfile.ZipFile(out / "ventas_ddl.zip", "w", zipfile.ZIP_DEFLATED) as zf:
    zf.write(out / "ventas_ddl.sql", "ventas_ddl.sql")
    zf.write(out / "README.md", "README.md")
PY

log "DDL exportado: ${OUT}/ventas_ddl.sql"
log "ZIP:           ${OUT}/ventas_ddl.zip"
log "Siguiente paso: súbelo a https://migration.enterprisedb.com/"
