# =============================================================================
# EPAS standalone para el laboratorio
#
# Las imágenes oficiales de EDB para Kubernetes están pensadas para ser
# orquestadas por el operador CloudNativePG: no traen un entrypoint que
# inicialice un clúster. Este Dockerfile toma la imagen oficial y añade un
# entrypoint mínimo para ejecutarla con Docker Compose.
#
# La imagen base es comercial. Debes autenticarte en docker.enterprisedb.com
# y pasar EDB_IMAGE como build-arg (lo hace docker/compose.yaml).
# =============================================================================
ARG EDB_IMAGE
FROM ${EDB_IMAGE}

ARG EDB_MAJOR=16
USER root

ENV EDB_HOME=/usr/edb/as${EDB_MAJOR} \
    PGBIN=/usr/edb/as${EDB_MAJOR}/bin \
    PGDATA=/var/lib/edb/as${EDB_MAJOR}/data \
    PATH=/usr/edb/as${EDB_MAJOR}/bin:$PATH \
    LANG=C.UTF-8

RUN mkdir -p "${PGDATA}" "$(dirname "${PGDATA}")/backups" /var/log/edb \
 && chown -R 26:26 "${PGDATA}" "$(dirname "${PGDATA}")" /var/log/edb \
 && chmod 700 "${PGDATA}"

COPY entrypoint.sh /usr/local/bin/edb-entrypoint.sh
RUN chmod 0755 /usr/local/bin/edb-entrypoint.sh

EXPOSE 5444

ENTRYPOINT ["/usr/local/bin/edb-entrypoint.sh"]
