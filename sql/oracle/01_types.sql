-- =============================================================================
-- 01_types.sql  |  Tipos definidos por el usuario (UDT)
--
-- Dos casos clásicos de Oracle que no se copian uno a uno a PostgreSQL/EPAS:
--   * Un objeto con atributos -> columnas planas, tipo compuesto o JSONB.
--   * Una colección anidada (nested table) -> arreglo, tabla hija o JSONB.
--
-- En este laboratorio:
--   T_DIRECCION  -> columnas dir_* en EPAS (decisión documentada).
--   T_TELEFONOS  -> text[] en EPAS + índice GIN.
-- =============================================================================
SET DEFINE OFF

CREATE OR REPLACE TYPE t_direccion AS OBJECT (
  calle          VARCHAR2(150),
  ciudad         VARCHAR2(80),
  estado         VARCHAR2(80),
  pais           CHAR(2),
  codigo_postal  VARCHAR2(12)
);
/

CREATE OR REPLACE TYPE t_telefonos AS TABLE OF VARCHAR2(30);
/

SHOW ERRORS
