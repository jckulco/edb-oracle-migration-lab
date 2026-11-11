-- =============================================================================
-- 00_reset.sql  |  Limpia el esquema VENTAS (Oracle)
--
-- Este script es DESTRUCTIVO y se ejecuta como el usuario VENTAS. No borra al
-- usuario ni sus privilegios; solo los objetos que le pertenecen. Se usa para
-- repetir el laboratorio sin recrear el contenedor.
--
-- Ejecución:
--   sqlplus ventas/<password>@//localhost:1521/FREEPDB1 @sql/oracle/00_reset.sql
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK OFF
WHENEVER SQLERROR CONTINUE

DECLARE
  PROCEDURE ejecutar(p_sql VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    DBMS_OUTPUT.PUT_LINE('OK   ' || p_sql);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('SKIP ' || p_sql || ' -> ' || SQLERRM);
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== Eliminando objetos del esquema ' || USER || ' ===');

  -- 1. Vistas materializadas (antes que las tablas base).
  FOR r IN (SELECT mview_name FROM user_mviews) LOOP
    ejecutar('DROP MATERIALIZED VIEW "' || r.mview_name || '"');
  END LOOP;

  -- 2. Vistas.
  FOR r IN (SELECT view_name FROM user_views) LOOP
    ejecutar('DROP VIEW "' || r.view_name || '"');
  END LOOP;

  -- 3. Unidades PL/SQL y triggers (los triggers también caen con las tablas).
  FOR r IN (
    SELECT object_name, object_type
      FROM user_objects
     WHERE object_type IN ('TRIGGER', 'PACKAGE BODY', 'PACKAGE', 'PROCEDURE', 'FUNCTION')
     ORDER BY CASE object_type
                WHEN 'TRIGGER'      THEN 1
                WHEN 'PACKAGE BODY' THEN 2
                WHEN 'PACKAGE'      THEN 3
                ELSE 4
              END
  ) LOOP
    BEGIN
      IF r.object_type = 'PACKAGE BODY' THEN
        ejecutar('DROP PACKAGE BODY "' || r.object_name || '"');
      ELSE
        ejecutar('DROP ' || r.object_type || ' "' || r.object_name || '"');
      END IF;
    END;
  END LOOP;

  -- 4. Tablas. La tabla anidada NT_TELEFONOS cae con CLIENTES.
  FOR r IN (
    SELECT table_name
      FROM user_tables
     WHERE table_name NOT LIKE 'NT\_%' ESCAPE '\'
       AND table_name NOT LIKE 'SYS\_%' ESCAPE '\'
       AND table_name NOT LIKE 'MLOG$\_%' ESCAPE '\'
  ) LOOP
    ejecutar('DROP TABLE "' || r.table_name || '" CASCADE CONSTRAINTS PURGE');
  END LOOP;

  -- 5. Secuencias propias (las identidades ISEQ$$_ caen con su tabla).
  FOR r IN (
    SELECT sequence_name
      FROM user_sequences
     WHERE sequence_name NOT LIKE 'ISEQ$$\_%' ESCAPE '\'
  ) LOOP
    ejecutar('DROP SEQUENCE "' || r.sequence_name || '"');
  END LOOP;

  -- 6. Tipos de usuario (después de eliminar tablas que los usan).
  FOR r IN (
    SELECT type_name
      FROM user_types
     WHERE type_name NOT LIKE 'SYS\_PLS\_%' ESCAPE '\'
  ) LOOP
    ejecutar('DROP TYPE "' || r.type_name || '" FORCE');
  END LOOP;

  -- 7. Sinónimos privados, si se agregaron en alguna práctica.
  FOR r IN (SELECT synonym_name FROM user_synonyms) LOOP
    ejecutar('DROP SYNONYM "' || r.synonym_name || '"');
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('=== Esquema limpio ===');
END;
/

SET FEEDBACK ON
