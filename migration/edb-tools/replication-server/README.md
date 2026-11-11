# EDB Replication Server y CDC

EDB Replication Server (EPRS) permite replicar cambios de Oracle a EPAS para
reducir el downtime de una migración. No se instala ni se automatiza en este
laboratorio: es un producto separado y su configuración depende de la versión,
la topología y el acceso al redo de Oracle.

## Cuándo usarlo

- El negocio no puede detener la aplicación durante horas.
- Se necesita un corte con ventana corta y fallback.
- Hay que mantener Oracle y EPAS sincronizados durante un período de prueba.
- Se requiere replicación bidireccional o multi-maestro (casos avanzados).

## Arquitectura típica

```text
Oracle (origen) ──► EPRS (captura CDC) ──► EPAS (destino)
        │                                      │
        └──── snapshot inicial ────────────────┘
```

Fases:

1. **Snapshot inicial**: copia consistente de las tablas a EPAS.
2. **CDC**: captura de cambios (insert/update/delete) desde Oracle.
3. **Sincronización**: aplicar cambios en EPAS con baja latencia.
4. **Validación**: comparar filas y reglas de negocio.
5. **Cutover**: detener escrituras en Oracle, vaciar la cola, cambiar la
   aplicación.
6. **Fallback**: si algo falla, revertir la aplicación a Oracle y reconciliar.

## Requisitos que debes verificar

- Versión de EPRS compatible con tu Oracle y EPAS.
- Licencia de EPRS.
- Conectividad bidireccional entre el host de EPRS, Oracle y EPAS.
- Usuario Oracle con privilegios de lectura del diccionario y acceso a los
  mecanismos de captura que exija tu versión (por ejemplo, redo/LogMiner).
- Espacio para la cola de replicación y para el snapshot.
- Estrategia de claves primarias: sin PK estable, el CDC es frágil.
- Manejo de LOBs, secuencias, triggers y DDL.
- Relojes sincronizados y zona horaria.

## Qué no cubre el laboratorio

- Instalación de EPRS.
- Configuración de replicación Oracle → EPAS.
- Pruebas de latencia, conflictos o failover.
- Sincronización de secuencias.
- DDL replication.

## Cómo lo integrarías

1. Levanta Oracle y EPAS con `make up`.
2. Carga el esquema y los datos iniciales con `make oracle-load` y
   `make edb-schema`.
3. Crea la publicación/suscripción de EPRS para el esquema `VENTAS`.
4. Haz el snapshot inicial.
5. Genera cambios en Oracle (por ejemplo, con `pkg_ventas.crear_pedido`).
6. Verifica que aparezcan en EPAS.
7. Ejecuta `make livecompare` o `make validate` para comparar.
8. Simula el corte: detén escrituras, espera la cola, cambia la aplicación.
9. Si falla, vuelve a Oracle y reconcilia.

## Checklist de CDC

- [ ] ¿EPRS está instalado y licenciado?
- [ ] ¿La versión soporta tu Oracle/EPAS?
- [ ] ¿El snapshot inicial es consistente?
- [ ] ¿Todas las tablas tienen PK?
- [ ] ¿Los LOBs/JSON/XML están soportados?
- [ ] ¿Los triggers de EPAS no duplican la lógica?
- [ ] ¿Las secuencias se gestionan aparte?
- [ ] ¿Hay monitoreo de lag y errores?
- [ ] ¿Se probó el cutover y el fallback?
- [ ] ¿LiveCompare/validate confirman la paridad?

## Referencias

- <https://www.enterprisedb.com/docs/eprs/latest/>
- <https://www.enterprisedb.com/docs/eprs/latest/01_introduction/>
