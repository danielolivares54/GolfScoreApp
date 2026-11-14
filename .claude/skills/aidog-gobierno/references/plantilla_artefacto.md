# Plantilla de artefacto de prompt (AIDOG)

Úsala para todo artefacto nuevo. Nombre: `ART_<dominio>_<tema>_vN`.

```text
### ARTEFACTO: ART_<dominio>_<tema>_vN (BORRADOR | VIGENTE)
**Fuente de verdad**: [documento/norma + versión/fecha]
**Criterios de validación** (verificables contra la fuente):
 1) [hecho concreto + referencia]
 2) [...]
 3) [...]
**Criterio de rechazo**: [errores que invalidan: terminología obsoleta, datos inventados, conclusiones sin evidencia]
---
**Rol**: [experto + jurisdicción/estándar]
**Contexto**: [usuario, situación, nivel]
**Tarea**: [acción concreta]
**Requisitos**:
 - Formato: [acorde al contenido, no un número fijo de puntos]
 - Cita la fuente de cada afirmación.
 - Si algo no es seguro o depende de versión, dilo; no inventes.
**Fuera de alcance**: [qué no debe cubrir]
**Ejemplo**: [fragmento de salida esperada]
**Autoverificación** (sí/no antes de entregar):
 - ¿Cada afirmación tiene fuente?
 - ¿Usé terminología vigente de la versión indicada?
 - ¿Cubrí [excepción clave]?
```

## Revisión de un artefacto (checklist)
Al analizar o mejorar un artefacto, revisa y reporta:
1. ¿La fuente de verdad tiene versión/fecha?
2. ¿Los criterios son verificables y correctos contra la fuente? (Un criterio puede codificar un error — ej. "obstáculo de agua" ya no existe en las Reglas de Golf 2023.)
3. ¿Algún criterio es más absoluto que la regla real?
4. ¿Los requisitos de formato chocan con el contenido necesario?
5. ¿Hay instrucción para incertidumbre y para "no evaluable"?
6. ¿La autoverificación es una lista sí/no, no una pregunta abierta?
