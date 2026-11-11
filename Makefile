# =============================================================================
# Makefile del laboratorio Oracle -> EDB Postgres Advanced Server
#
#   make help          Lista de objetivos
#   make all           Flujo completo (sin validación final)
#   make validate      Compara datos y ejecuta pruebas funcionales
# =============================================================================
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PYTHON ?= $(ROOT)/.venv/bin/python
COMPOSE ?= docker compose --env-file $(ROOT)/.env -f $(ROOT)/docker/compose.yaml
SCRIPTS := $(ROOT)/scripts

.DEFAULT_GOAL := help

.PHONY: help env venv check up down reset logs ps oracle-load oracle-cli \
        assess edb-schema migrate post-load validate benchmark all test lint \
        ci clean clean-reports reports

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nLaboratorio Oracle -> EPAS\n\nUso: make <objetivo>\n\n"} \
	/^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n"

env: ## Crea .env a partir de .env.example si no existe
	@test -f "$(ROOT)/.env" || cp "$(ROOT)/.env.example" "$(ROOT)/.env"
	@echo "Archivo .env listo. Revisa EDB_IMAGE y las contraseñas."

venv: ## Crea el virtualenv e instala dependencias
	python3 -m venv "$(ROOT)/.venv"
	"$(ROOT)/.venv/bin/python" -m pip install --upgrade pip
	"$(ROOT)/.venv/bin/pip" install -r "$(ROOT)/migration/requirements-dev.txt"

check: ## Verifica Docker, Compose, Python y configuración
	$(SCRIPTS)/00_check.sh

up: ## Levanta Oracle y EPAS
	$(SCRIPTS)/01_up.sh

down: ## Detiene los contenedores (conserva datos)
	$(SCRIPTS)/09_down.sh

reset: ## Reconstruye todo desde cero (borra volúmenes)
	$(SCRIPTS)/99_reset.sh --yes

logs: ## Sigue los logs de ambos contenedores
	$(COMPOSE) logs -f --tail=100

ps: ## Estado de los contenedores
	$(COMPOSE) ps

oracle-load: ## Crea y carga el esquema Oracle
	$(SCRIPTS)/02_load_oracle.sh

oracle-cli: ## Abre SQL*Plus como VENTAS
	@set -a; source "$(ROOT)/.env"; set +a; \
	$(COMPOSE) exec oracle sqlplus -S "$$ORACLE_APP_USER/$$ORACLE_APP_PASSWORD@//localhost:1521/$$ORACLE_PDB"

assess: ## Genera el assessment del esquema Oracle
	$(SCRIPTS)/03_assess.sh

edb-schema: ## Crea el esquema destino en EPAS
	$(SCRIPTS)/04_create_edb_schema.sh

migrate: ## Migra los datos Oracle -> EPAS
	$(SCRIPTS)/05_migrate_data.sh

post-load: ## Crea índices, FKs, vistas, MV, paquetes y triggers
	$(SCRIPTS)/06_post_load.sh

validate: ## Valida datos y pruebas funcionales
	$(SCRIPTS)/07_validate.sh

benchmark: ## Ejecuta el benchmark indicativo
	$(SCRIPTS)/08_benchmark.sh

all: up oracle-load edb-schema migrate post-load ## Flujo completo sin validación
	@echo "Flujo completo. Ejecuta: make validate"

test: ## Ejecuta las pruebas unitarias
	$(PYTHON) -m pytest

lint: ## Ruff + compilación Python + sintaxis Bash
	$(PYTHON) -m ruff check migration tests
	$(PYTHON) -m compileall -q migration tests
	@for f in $(SCRIPTS)/*.sh $(SCRIPTS)/lib/*.sh \
	           $(ROOT)/docker/oracle/init/*.sh $(ROOT)/docker/edb/*.sh; do \
	  echo "bash -n $$f"; bash -n "$$f"; \
	done

ci: lint test ## Lo que ejecuta GitHub Actions

reports: ## Lista los reportes generados
	@ls -lh "$(ROOT)/migration/reports" 2>/dev/null || true

clean-reports: ## Borra los reportes generados
	@find "$(ROOT)/migration/reports" -type f ! -name '.gitkeep' -delete

clean: clean-reports ## Borra virtualenv, cachés y reportes
	rm -rf "$(ROOT)/.venv" "$(ROOT)/.pytest_cache"
	find "$(ROOT)" -type d -name __pycache__ -prune -exec rm -rf {} +
