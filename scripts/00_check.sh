#!/usr/bin/env bash
# =============================================================================
# 00_check.sh  |  Verifica prerrequisitos sin modificar nada.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_docker
require_env
require_cmd python3

log "Docker:        $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?')"
log "Compose:       $(docker compose version --short 2>/dev/null || echo '?')"
log "Python:        $(python3 --version)"
log "Proyecto:      ${ROOT_DIR}"
log "Imagen Oracle: ${ORACLE_IMAGE:-gvenzl/oracle-free:23-slim}"
log "Imagen EPAS:   ${EDB_IMAGE}"

python3 - <<'PY'
import sys
if sys.version_info < (3, 11):
    raise SystemExit("Se requiere Python 3.11 o superior")
print("Python >= 3.11: OK")
PY

if docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" config --quiet; then
  log "docker compose config: OK"
else
  die "docker compose config falló. Revisa .env y docker/compose.yaml"
fi

for port in "${ORACLE_PORT:-1521}" "${EDB_PORT:-5444}"; do
  if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":${port} "; then
    warn "El puerto ${port} ya está en escucha en el host; puede haber un conflicto."
  fi
done

if [[ ! -x "${PYTHON}" ]]; then
  warn "No existe el virtualenv. Ejecuta: make venv"
fi

if ! grep -q '^EDB_IMAGE=.*' "${ENV_FILE}"; then
  warn "EDB_IMAGE no está definido en .env"
fi

log "Comprobaciones completadas. Siguiente paso: make up"
