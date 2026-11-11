#!/usr/bin/env bash
# =============================================================================
# 14_tools_status.sh  |  Comprueba qué herramientas EDB están disponibles.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env

status() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  %-28s OK\n' "${name}"
  else
    printf '  %-28s NO DISPONIBLE\n' "${name}"
  fi
}

echo "Herramientas EDB en el host:"
status "java" java -version
status "Migration Toolkit (runMTK.sh)" bash -lc 'command -v runMTK.sh || test -x "${MTK_HOME:-/usr/edb/migrationtoolkit}/bin/runMTK.sh"'
status "LiveCompare" bash -c 'command -v "${LIVECOMPARE_BIN:-livecompare}"'
status "Ora2Pg" command -v ora2pg

echo
echo "Herramientas dentro de EPAS:"
status "edbldr" compose exec -T edb bash -c 'command -v edbldr'
status "edb-psql" compose exec -T edb bash -c 'command -v edb-psql'

echo
echo "Servicios web / productos:"
echo "  Migration Portal             https://migration.enterprisedb.com/"
echo "  Migration Portal AI Copilot  integrado en Migration Portal"
echo "  Replication Server           producto/instalación separada (ver docs/22)"
echo
echo "Documentación local: migration/edb-tools/README.md"
