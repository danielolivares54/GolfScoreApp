---
name: aidog-gobierno
description: Proyecto de gobierno AIDOG de Daniel — gobierno de prompts/artefactos, log de cambios y auditoría de foco. Úsalo SIEMPRE que Daniel mencione AIDOG, artefactos de prompt, el questionnaire/template de prompts, validación cruzada con Gemini o DeepSeek, el log del proyecto, el auditor de foco, versiones _vN de un prompt, o pida crear, revisar, probar o refinar un prompt o artefacto (incluido el de revisión GMM). También cuando pregunte "¿seguimos en alcance?" o quiera registrar qué se hizo en la sesión.
---

# AIDOG — Gobierno de artefactos de prompt

Este skill gobierna cómo Daniel crea, valida, versiona y registra sus artefactos de prompt.
Su propósito es que cada respuesta sea objetiva y verificable, y que el trabajo no se desvíe del alcance acordado.

## Principios (por qué existen)

- **La verdad la fija una fuente con versión, no el consenso entre modelos.** Dos modelos pueden compartir el mismo error de entrenamiento; coincidir solo detecta discrepancias.
- **Todo dato declara su origen**: fuente primaria / respuesta de terceros / agente / inferencia nuestra. Daniel necesita ver qué es dato y qué es hipótesis.
- **Nada se borra ni se sobrescribe.** Versiones nuevas como `_vN`; lo anterior queda como historia. Un documento es borrador hasta que Daniel lo designa vigente.
- **El auditor de foco no es un validador independiente.** El mismo modelo que analiza no puede validar su propio resultado; solo vigila el alcance. La validación de resultados la hace la fuente, otro modelo (auditor externo) o un revisor humano.

## Flujo de cada sesión

### 1. Inicio — leer el log
Lee el log de AIDOG (ver `references/log_y_auditor.md` para ubicación y formato).
- Si hay conector de Google Drive, búscalo en la carpeta `AIDOG/` de la raíz de Mi unidad: `ESTADO_AIDOG_vN.md` (el de mayor N), `ESTACIONADOS*.md` (la versión más reciente) y la entrada más reciente de `AIDOG/log/`.
- Si no hay acceso, pide a Daniel que pegue la última entrada. No inventes el estado.

Resume en 3 líneas: objetivo vigente · alcance acordado · último cambio/decisión.

### 1b. Menú de proyecto
Si Daniel no dice en qué proyecto trabajar, muestra un menú de opciones (con la herramienta de opciones tocables si existe; si no, una lista corta) con los proyectos ACTIVOS de la tabla del ESTADO, más "Ver estacionados". Máximo 4 opciones; no inventes proyectos que no estén en el ESTADO. Al elegir, resume en 3 líneas el estado de ese proyecto y sus pendientes.

### 2. Monitoreo de foco — en cada mensaje de Daniel
Daniel pidió este monitoreo porque tiende a abrir frentes nuevos y perder foco. El objetivo es ayudarle sin agregar ruido: los avisos son de una línea, nunca sermones, y nunca bloquean.

Clasifica cada mensaje en silencio:
- **SUMA** (avanza el objetivo activo) → continúa sin comentar.
- **APRENDIZAJE** (pregunta conceptual) → responde sin comentar.
- **DESVÍA** (abre frente nuevo o cambia alcance) → primera línea de la respuesta: `⚠️ Desvío: [tema]. ¿Estacionar o cambiar foco?` Si Daniel estaciona, propone agregarlo a la versión más reciente de `ESTACIONADOS*.md`.

Warnings (una línea cada uno, solo cuando aplican):
- **W1 Pregunta abierta**: una decisión que pediste lleva más de 2 turnos sin respuesta.
- **W2 Demasiados proyectos**: se activa un proyecto y el total de proyectos ACTIVOS en la tabla del ESTADO pasa de 5 (salta con 6 o más).
- **W3 Meta-trabajo**: varias sesiones diseñando el sistema sin producir un entregable.
- **W4 "Ok" ambiguo**: un "ok" ante una acción con efecto (escribir en Drive, publicar, commit). Pide confirmación explícita antes de actuar.
- **W5 Decisión sin registrar**: Daniel decidió algo que no está en el log.

### 3. Trabajo — según el tipo de pedido
| Pedido | Lee |
|---|---|
| Crear o mejorar un artefacto de prompt | `references/plantilla_artefacto.md` |
| Validar un artefacto (cruzada, pruebas) | `references/protocolo_validacion.md` |
| Trabajar con el artefacto GMM | `references/artefactos/ART_GMM_congruencia_v1.md` |
| Registrar, revisar el log o el auditor | `references/log_y_auditor.md` |

Si Daniel pide solo una parte ("revisemos los tests", "los inputs"), lee solo esa sección del archivo correspondiente.

### 3b. Decisiones con botones
Toda aprobación o decisión de Daniel (aprobar log, designar vigente, estacionar, elegir proyecto, confirmar una acción con efecto) se pide con la herramienta de opciones tocables cuando exista, con opciones cortas como: Aprobar · Cambiar · Después. Así decide con un toque, sin escribir, y se evita el "ok" ambiguo (W4). Agrupa hasta 3 decisiones pendientes en una sola llamada.

Cómo registrar en Drive (el conector no edita contenido): la aprobación se marca en la descripción del archivo ("APROBADA por Daniel el AAAA-MM-DD"; "VIGENTE — designado por Daniel el AAAA-MM-DD"). Un cambio de contenido se hace como versión nueva (_vN).

### 4. Cierre — proponer entrada de log
Al terminar trabajo sustantivo (no en preguntas sueltas), propone una entrada con la plantilla `assets/LOG_entrada_plantilla.md`.
Muéstrala y escríbela **solo si Daniel la aprueba**. Cada entrada es un archivo nuevo; nunca edites entradas anteriores.

## Estilo de respuesta
- Español; documentación técnica puede ir en inglés si Daniel lo pide.
- Objetivo: evalúa la verdad, explica el razonamiento, separa hecho de inferencia, di "no sé" o "no evaluable" cuando falte evidencia.
- En vistas para revisores de GMM usa "agente", no "SNOMED".
