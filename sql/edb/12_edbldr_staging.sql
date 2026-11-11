-- =============================================================================
-- 12_edbldr_staging.sql  |  Tabla de staging para la demo de EDB*Loader
--
-- EDB*Loader es el cargador masivo compatible con SQL*Loader de Oracle.
-- Esta tabla NO forma parte del modelo principal: es un sandbox para mostrar
-- cómo se carga un archivo .dat con un archivo de control .ctl.
-- =============================================================================
SET search_path TO ventas, public;

DROP TABLE IF EXISTS regiones_ldr;

CREATE TABLE regiones_ldr (
  region_id bigint      NOT NULL,
  nombre    varchar(60) NOT NULL,
  codigo    char(2)     NOT NULL
);

COMMENT ON TABLE regiones_ldr IS
  'Sandbox para la demostración de EDB*Loader (migration/edb-tools/edbldr)';
