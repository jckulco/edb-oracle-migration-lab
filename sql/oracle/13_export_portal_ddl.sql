-- =============================================================================
-- 13_export_portal_ddl.sql  |  Exporta DDL Oracle para Migration Portal
--
-- Migration Portal acepta un archivo .sql con el DDL del esquema. Este script
-- usa DBMS_METADATA para generar un volcado limpio (sin storage/tablespace) de
-- tipos, secuencias, tablas, constraints, índices, vistas, MVs, paquetes,
-- procedimientos, funciones y triggers.
--
-- El SPOOL queda dentro del contenedor en /tmp/ventas_ddl.sql. El wrapper
-- scripts/11_portal_export.sh lo copia a migration/reports/portal/.
--
-- Ejecutar como VENTAS:
--   sqlplus ventas/<password>@//localhost:1521/FREEPDB1 @13_export_portal_ddl.sql
-- =============================================================================
SET LONG 2000000
SET LONGCHUNKSIZE 2000000
SET PAGESIZE 0
SET HEADING OFF
SET FEEDBACK OFF
SET ECHO OFF
SET TRIMSPOOL ON
SET LINESIZE 32767
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

SPOOL /tmp/ventas_ddl.sql

DECLARE
  PROCEDURE imprimir_clob(p_texto IN CLOB) IS
    v_len   CONSTANT PLS_INTEGER := 32000;
    v_pos   PLS_INTEGER := 1;
    v_total PLS_INTEGER;
  BEGIN
    IF p_texto IS NULL THEN
      RETURN;
    END IF;
    v_total := DBMS_LOB.GETLENGTH(p_texto);
    WHILE v_pos <= v_total LOOP
      DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(p_texto, v_len, v_pos));
      v_pos := v_pos + v_len;
    END LOOP;
  END imprimir_clob;

  PROCEDURE emitir(p_tipo IN VARCHAR2, p_nombre IN VARCHAR2) IS
    v_ddl CLOB;
  BEGIN
    v_ddl := DBMS_METADATA.GET_DDL(p_tipo, p_nombre);
    imprimir_clob(v_ddl);
    DBMS_OUTPUT.PUT_LINE('/');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('-- ERROR ' || p_tipo || ' ' || p_nombre ||
                           ': ' || SQLERRM);
  END emitir;
BEGIN
  -- DDL limpio y portable: sin storage, tablespaces ni índices implícitos.
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'PRETTY', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', TRUE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'TABLESPACE', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'CONSTRAINTS', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'REF_CONSTRAINTS', FALSE);
  DBMS_METADATA.SET_TRANSFORM_PARAM(
    DBMS_METADATA.SESSION_TRANSFORM, 'INDEXES', FALSE);

  DBMS_OUTPUT.PUT_LINE('-- Esquema: ' || USER);
  DBMS_OUTPUT.PUT_LINE('-- Generado para EDB Migration Portal');

  -- 1. Tipos
  FOR r IN (
    SELECT type_name
      FROM user_types
     WHERE type_name NOT LIKE 'SYS\_PLS\_%' ESCAPE '\'
     ORDER BY type_name
  ) LOOP
    emitir('TYPE', r.type_name);
  END LOOP;

  -- 2. Secuencias (excluye las internas de identidad)
  FOR r IN (
    SELECT sequence_name
      FROM user_sequences
     WHERE sequence_name NOT LIKE 'ISEQ$$\_%' ESCAPE '\'
     ORDER BY sequence_name
  ) LOOP
    emitir('SEQUENCE', r.sequence_name);
  END LOOP;

  -- 3. Tablas (excluye nested tables y contenedores de MV)
  FOR r IN (
    SELECT t.table_name
      FROM user_tables t
     WHERE t.table_name NOT LIKE 'NT\_%' ESCAPE '\'
       AND t.table_name NOT LIKE 'MLOG$\_%' ESCAPE '\'
       AND NOT EXISTS (SELECT 1 FROM user_mviews m
                        WHERE m.mview_name = t.table_name)
     ORDER BY t.table_name
  ) LOOP
    emitir('TABLE', r.table_name);
  END LOOP;

  -- 4. Constraints e índices
  FOR r IN (
    SELECT constraint_name
      FROM user_constraints
     WHERE constraint_name NOT LIKE 'SYS\_%' ESCAPE '\'
     ORDER BY constraint_name
  ) LOOP
    emitir('CONSTRAINT', r.constraint_name);
  END LOOP;

  FOR r IN (
    SELECT i.index_name
      FROM user_indexes i
     WHERE i.index_name NOT LIKE 'SYS\_%' ESCAPE '\'
       AND NOT EXISTS (
         SELECT 1 FROM user_constraints c
          WHERE c.index_name = i.index_name)
     ORDER BY i.index_name
  ) LOOP
    emitir('INDEX', r.index_name);
  END LOOP;

  -- 5. Vistas y vistas materializadas
  FOR r IN (SELECT view_name FROM user_views ORDER BY view_name) LOOP
    emitir('VIEW', r.view_name);
  END LOOP;

  FOR r IN (SELECT mview_name FROM user_mviews ORDER BY mview_name) LOOP
    emitir('MATERIALIZED_VIEW', r.mview_name);
  END LOOP;

  -- 6. Unidades PL/SQL
  FOR r IN (
    SELECT object_name, object_type
      FROM user_objects
     WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'PROCEDURE', 'FUNCTION')
     ORDER BY CASE object_type
                WHEN 'PACKAGE' THEN 1
                WHEN 'PACKAGE BODY' THEN 2
                WHEN 'PROCEDURE' THEN 3
                ELSE 4
              END, object_name
  ) LOOP
    IF r.object_type = 'PACKAGE' THEN
      emitir('PACKAGE_SPEC', r.object_name);
    ELSIF r.object_type = 'PACKAGE BODY' THEN
      emitir('PACKAGE_BODY', r.object_name);
    ELSIF r.object_type = 'PROCEDURE' THEN
      emitir('PROCEDURE', r.object_name);
    ELSE
      emitir('FUNCTION', r.object_name);
    END IF;
  END LOOP;

  -- 7. Triggers
  FOR r IN (SELECT trigger_name FROM user_triggers ORDER BY trigger_name) LOOP
    emitir('TRIGGER', r.trigger_name);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('-- Fin del DDL');
END;
/

SPOOL OFF
EXIT
