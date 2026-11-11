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
