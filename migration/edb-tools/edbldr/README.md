# EDB\*Loader (edbldr)

EDB\*Loader es el cargador masivo de EPAS compatible con SQL\*Loader de
Oracle. Este laboratorio lo usa para cargar un archivo `.dat` en una tabla
sandbox `ventas.regiones_ldr`.

## Archivos

- `regiones.ctl`: control file con `LOAD DATA`, `TRUNCATE`, `FIELDS TERMINATED BY ','`.
- `regiones.dat`: datos de las cuatro regiones.
- `../../sql/edb/12_edbldr_staging.sql`: crea la tabla.
- `scripts/13_edbldr.sh`: orquesta la carga dentro del contenedor.

## Ejecución

```bash
make edbldr-demo
```

El script:

1. Crea `ventas.regiones_ldr`.
2. Copia `.ctl`/`.dat` a `/tmp/edbldr` en el contenedor.
3. Ejecuta:
   ```bash
   edbldr -d ventas -p 5444 -h 127.0.0.1 \
     USERID=ventas/... CONTROL=regiones.ctl DATA=regiones.dat \
     BAD=regiones.bad DISCARD=regiones.dsc LOG=regiones.log
   ```
4. Verifica que haya 4 filas.

## Control file

```text
LOAD DATA
  INFILE 'regiones.dat'
    BADFILE 'regiones.bad'
    DISCARDFILE 'regiones.dsc'
  TRUNCATE
  INTO TABLE regiones_ldr
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    TRAILING NULLCOLS
  (
    region_id,
    nombre,
    codigo
  )
```

`TRUNCATE` hace la carga repetible. En producción, `APPEND` o `INSERT` según
el caso.

## Cuándo usar EDB\*Loader

- Archivos planos grandes.
- Migración de datos exportados de Oracle (CSV/posicional).
- Cargas repetibles y controladas.
- Cuando ya tienes un `.ctl` de SQL\*Loader y quieres reutilizarlo.

## Limitaciones

- No traduce tipos Oracle; la tabla destino debe existir con tipos EPAS.
- Los LOBs y formatos complejos requieren revisión.
- `DIRECT=TRUE` no es compatible con tablas replicadas.
- `HANDLE_CONFLICTS` no funciona con direct path.
- Los nombres de archivo deben respetar las extensiones `.ctl`, `.dat`,
  `.bad`, `.dsc`, `.log`.
- El usuario debe tener permisos de inserción/truncado sobre la tabla.

## Referencias

- <https://www.enterprisedb.com/docs/epas/latest/database_administration/02_edb_loader/>
- <https://www.enterprisedb.com/docs/epas/latest/database_administration/02_edb_loader/building_the_control_file/control_file_examples/>
- <https://www.enterprisedb.com/docs/epas/latest/database_administration/02_edb_loader/invoking_edb_loader/running_edb_loader/>
