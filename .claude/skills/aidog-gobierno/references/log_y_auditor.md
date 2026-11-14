# Log y auditor de foco (AIDOG)

## Ubicación
- Google Drive: `AIDOG/log/` (carpeta AIDOG en la raíz de Mi unidad)
- Una entrada por archivo: `AAAA-MM-DD_<tema-corto>.md` (append-only natural: nunca se reescribe un archivo existente).
- Estado vigente: `AIDOG/ESTADO_AIDOG_vN.md` (objetivo, alcance, artefactos vigentes). Cambia solo con aprobación de Daniel, como versión nueva.

## Por qué el log no vive en el skill
En claude.ai los skills son de solo lectura para Claude. El skill contiene las instrucciones; Drive contiene la historia.

## Reglas del log
- Se escribe solo con aprobación de Daniel.
- Nunca se borran ni editan entradas anteriores; una corrección es una entrada nueva que referencia la anterior.
- Cada entrada indica si se hizo la auditoría de foco (sí/no), para detectar cuándo falla.
- Distinguir: decisión de Daniel vs. propuesta de Claude. Una sugerencia aceptada con "ok" se registra como "Daniel aprobó el enfoque", no como cada detalle.

## Auditor de foco
- Compara cada pedido con el alcance en `ESTADO_AIDOG_vN.md`.
- Marca desvíos en una línea con la regla de SKILL.md (`⚠️ Desvío: [tema]. ¿Estacionar o cambiar foco?`). El aviso no bloquea: Claude sigue respondiendo y Daniel decide cuando quiera.
- No valida resultados; solo alcance.
- Límite conocido: el skill solo se carga cuando la conversación coincide con su descripción. En chats que no lo invocan no hay monitoreo ni log. Para que corra en todo un proyecto de claude.ai, las instrucciones del proyecto deben decir que se use aidog-gobierno.

## Estacionados
La versión más reciente de `AIDOG/ESTACIONADOS*.md` (ESTACIONADOS.md o ESTACIONADOS_vN.md): ideas guardadas sin abrir (fecha, idea, origen, nota). Reabrir una idea es decisión de Daniel.

## Proyectos con repo (ej. Caddie Score)
Sus archivos AIDOG viven en el repo (`docs/AIDOG/`) y los administra el agente de Xcode; en Drive queda solo una copia de referencia.
