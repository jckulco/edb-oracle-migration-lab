# 22. EDB Replication Server y CDC

## Qué aporta

EDB Replication Server (EPRS) replica cambios de Oracle a EPAS. En una
migración sirve para:

- Reducir el downtime: snapshot inicial + captura de cambios (CDC).
- Mantener Oracle y EPAS sincronizados durante la prueba.
- Permitir un fallback si el corte falla.
- Hacer una migración por fases sin apagar la aplicación.

Es un producto separado. El laboratorio **no lo instala ni lo automatiza**;
documenta el diseño, los requisitos y el checklist.

## Arquitectura

```text
Oracle (origen)
   │  redo/CDC
   ▼
EDB Replication Server
   │  cambios aplicados
   ▼
EPAS (destino)

Snapshot inicial: Oracle ─────────────► EPAS
```

## Fases

### 1. Snapshot inicial

Copia consistente del esquema y los datos. En el laboratorio puedes usar:

- `make migrate` (ETL propio).
- MTK offline/online en un esquema aislado.
- EDB\*Loader para tablas concretas.

### 2. CDC

EPRS captura inserts/updates/deletes de Oracle y los aplica en EPAS. Necesita
una configuración específica de publicación/suscripción y acceso a los
mecanismos de captura de Oracle.

### 3. Validación continua

- `make validate` para checksums y pruebas funcionales.
- `make livecompare` para comparación fila a fila.
- Monitoreo de lag y errores de replicación.

### 4. Cutover

1. Congelar escrituras en Oracle (o modo mantenimiento).
2. Esperar a que la cola de EPRS llegue a cero.
3. Ejecutar la validación final.
4. Cambiar la aplicación a EPAS.
5. Mantener Oracle en solo lectura para rollback.

### 5. Fallback

Si falla:

1. Detener la aplicación.
2. Revertir la conexión a Oracle.
3. Reconciliar los cambios que hayan ido a EPAS.
4. Documentar y analizar.

## Requisitos a verificar

- Versión de EPRS compatible con Oracle y EPAS.
- Licencia.
- Conectividad bidireccional.
- Usuario Oracle con privilegios de lectura del diccionario y captura.
- Espacio para colas y snapshots.
- PK estables en todas las tablas.
- Soporte de LOBs/JSON/XML.
- Manejo de secuencias y triggers.
- Relojes y zonas horarias.
- Plan de monitoreo y alertas.

## Qué no hace el laboratorio

- Instalar EPRS.
- Configurar publicaciones/suscripciones.
- Probar conflictos o failover.
- Replicar DDL.
- Sincronizar secuencias.

## Cómo practicarlo

1. Levanta Oracle y EPAS.
2. Carga el esquema con `make oracle-load` y `make edb-schema`.
3. Haz el snapshot con `make migrate`.
4. Configura EPRS para `VENTAS` (fuera del repositorio).
5. Genera cambios:
   ```sql
   BEGIN
     pkg_ventas.crear_pedido(3, 10, 2, :id);
   END;
   ```
6. Verifica que el pedido aparezca en EPAS.
7. Compara con `make livecompare` o `make validate`.
8. Simula el corte y el fallback.

## Checklist de CDC

- [ ] ¿EPRS instalado y licenciado?
- [ ] ¿Versiones compatibles?
- [ ] ¿Snapshot consistente?
- [ ] ¿Todas las tablas tienen PK?
- [ ] ¿LOBs/JSON/XML soportados?
- [ ] ¿Los triggers de EPAS no duplican lógica?
- [ ] ¿Secuencias gestionadas aparte?
- [ ] ¿Monitoreo de lag/errores?
- [ ] ¿Cutover probado?
- [ ] ¿Fallback probado?
- [ ] ¿LiveCompare/validate confirman paridad?

## Referencias

- <https://www.enterprisedb.com/docs/eprs/latest/>
- <https://www.enterprisedb.com/docs/eprs/latest/01_introduction/>
- <https://www.enterprisedb.com/docs/eprs/latest/02_installation/>
