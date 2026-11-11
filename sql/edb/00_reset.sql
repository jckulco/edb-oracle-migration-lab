-- =============================================================================
-- 00_reset.sql  |  Reinicia el esquema de destino en EPAS
--
-- Se conecta como el usuario VENTAS (dueño de la base y del esquema).
-- Elimina el esquema completo y lo vuelve a crear. ¡Destructivo!
--
-- Ejecución:
--   psql "host=localhost port=5444 dbname=ventas user=ventas" \
--        -v ON_ERROR_STOP=1 -f sql/edb/00_reset.sql
-- =============================================================================
\set ON_ERROR_STOP on

SET client_min_messages = warning;

-- La extensión edbspl la crea el entrypoint como superusuario en public.
-- Si usas un EPAS externo, ejecuta una vez: CREATE EXTENSION edbspl;
SET search_path TO public;
DROP SCHEMA IF EXISTS ventas CASCADE;
CREATE SCHEMA ventas AUTHORIZATION ventas;

SET search_path TO ventas, public;

COMMENT ON SCHEMA ventas IS
  'Esquema de destino del laboratorio Oracle -> EDB Postgres Advanced Server';
