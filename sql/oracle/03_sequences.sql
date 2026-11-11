-- =============================================================================
-- 03_sequences.sql  |  Secuencias Oracle
--
-- Se usan dos patrones a propósito:
--   * Secuencia + trigger BEFORE INSERT (clientes, pedidos, pagos, direcciones).
--   * Identidad nativa (productos, pedido_detalle, auditoria).
--
-- La migración conserva los valores y resincroniza las secuencias al final.
-- =============================================================================
SET DEFINE OFF

CREATE SEQUENCE seq_clientes    START WITH 1 INCREMENT BY 1 CACHE 20 NOCYCLE;
CREATE SEQUENCE seq_direcciones START WITH 1 INCREMENT BY 1 CACHE 20 NOCYCLE;
CREATE SEQUENCE seq_pedidos     START WITH 1 INCREMENT BY 1 CACHE 20 NOCYCLE;
CREATE SEQUENCE seq_pagos       START WITH 1 INCREMENT BY 1 CACHE 20 NOCYCLE;
CREATE SEQUENCE seq_historial   START WITH 1 INCREMENT BY 1 CACHE 20 NOCYCLE;

SHOW ERRORS
