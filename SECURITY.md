# Política de seguridad

Este es un laboratorio educativo, no un sistema productivo.

## Qué no debe hacerse

- No publiques el archivo `.env` ni credenciales reales.
- No ejecutes este laboratorio expuesto a Internet: los puertos de Oracle y
  EPAS se publican en el host y las contraseñas de ejemplo son débiles.
- No reutilices las contraseñas de ejemplo en ambientes corporativos.
- No subas volcados con datos personales o de clientes.

## Reportar una vulnerabilidad

Si encuentras una vulnerabilidad en el código del laboratorio (por ejemplo,
inyección SQL en los scripts, un `Dockerfile` inseguro o una dependencia
vulnerable), abre un issue privado o contacta a los mantenedores. Incluye:

1. Descripción del problema.
2. Pasos para reproducirlo.
3. Impacto potencial.
4. Versión o commit afectado.

## Dependencias

Las dependencias de Python están fijadas en `migration/requirements.txt`.
Revisa periódicamente `pip-audit` o el aviso de GitHub Dependabot.
