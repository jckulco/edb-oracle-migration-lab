# Guía de contribución

Gracias por querer mejorar este laboratorio. El objetivo es mantener un
proyecto reproducible, didáctico y seguro para aprender a migrar Oracle a
EDB Postgres Advanced Server (EPAS).

## Cómo proponer cambios

1. Abre un *issue* describiendo el problema o la mejora.
2. Crea una rama: `git switch -c feat/mi-aporte`.
3. Realiza cambios pequeños y enfocados.
4. Ejecuta las verificaciones locales:
   ```bash
   make lint
   make test
   ```
5. Abre un *pull request* explicando qué cambia y cómo lo probaste.

## Reglas para SQL y scripts

- Todo el texto, comentarios y documentación va en **español**.
- No incluyas credenciales reales, cadenas de conexión ni volcados de datos.
- Los scripts deben ser idempotentes o fallar con un mensaje claro.
- Usa `set -euo pipefail` en Bash.
- Valida los identificadores que se interpolan en SQL.
- Añade comentarios explicando el *porqué* de las decisiones de migración.
- Si agregas un objeto Oracle, añade su equivalente EPAS y su prueba.
- Si un objeto no tiene equivalente directo, documenta la brecha y la
  alternativa recomendada.

## Estilo

- Markdown con líneas de hasta ~100 caracteres cuando sea razonable.
- SQL en minúsculas para EPAS y mayúsculas para Oracle, siguiendo la
  convención de cada motor.
- Nombres de archivos numéricos para indicar el orden de ejecución.
- Commits en imperativo: `docs: explica el mapeo de XMLTYPE`.

## Licencia de las contribuciones

Al enviar un *pull request* aceptas que tu contribución se publique bajo la
licencia MIT de este repositorio.
