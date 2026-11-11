#!/usr/bin/env bash
# =============================================================================
# Concesiones adicionales para el usuario de aplicación de Oracle.
#
# Los scripts *.sql de /container-entrypoint-initdb.d se ejecutan como SYS en
# el CDB. Este script corre como el usuario oracle del sistema operativo y se
# conecta con autenticación local (/ as sysdba), entra a FREEPDB1 y otorga los
# privilegios que Oracle Database Free no incluye en CONNECT/RESOURCE.
#
# Se ejecuta UNA sola vez, durante la inicialización del contenedor.
# =============================================================================
set -euo pipefail

APP_USER="${APP_USER:?APP_USER no está definido}"
ORACLE_PDB="${ORACLE_PDB:-FREEPDB1}"

# Validación defensiva: los identificadores se interpolan en SQL*Plus.
if [[ ! "$APP_USER" =~ ^[A-Za-z][A-Za-z0-9_\$#]*$ ]]; then
  echo "ERROR: APP_USER contiene caracteres no permitidos: $APP_USER" >&2
  exit 1
fi
if [[ ! "$ORACLE_PDB" =~ ^[A-Za-z][A-Za-z0-9_\$#]*$ ]]; then
  echo "ERROR: ORACLE_PDB contiene caracteres no permitidos: $ORACLE_PDB" >&2
  exit 1
fi

echo "[oracle-init] Otorgando privilegios a ${APP_USER} en ${ORACLE_PDB}..."

sqlplus -s / as sysdba <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = ${ORACLE_PDB};

GRANT CREATE MATERIALIZED VIEW, CREATE DATABASE LINK, CREATE JOB,
      CREATE SYNONYM, CREATE VIEW, CREATE TYPE, CREATE PROCEDURE,
      CREATE SEQUENCE, CREATE TRIGGER, CREATE TABLE, CREATE INDEX
   TO ${APP_USER};

ALTER USER ${APP_USER} QUOTA UNLIMITED ON USERS;

-- Necesario para pkg_mantenimiento.refrescar_mv (DBMS_MVIEW.REFRESH).
GRANT EXECUTE ON DBMS_MVIEW TO ${APP_USER};

EXIT
SQL

echo "[oracle-init] Privilegios aplicados."
