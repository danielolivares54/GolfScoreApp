# Caddy_Score

Responde en español.

<!-- Origen: este archivo lo generó el 27-oct-2026 una sesión de Claude en el proyecto
     prototipo "Voz Caddie" / "Caddie Watch" (~/Documents/Caddie Watch). Allí se definió la
     spec del reloj y se descubrió que el proyecto real es este. Si falta contexto, el brief
     de esa sesión está en docs/BRIEF_DESDE_PROTOTIPO_CADDIE_WATCH.md. -->

## Trabajo en curso: experiencia del reloj durante el match

Antes de tocar el reloj (target `CaddieWatch Watch App`, `WatchShared/`), lee:

@docs/BRIEF_DESDE_PROTOTIPO_CADDIE_WATCH.md
@docs/WATCH_EXPERIENCIA_MATCH_SPEC.md
@docs/WATCH_VOZ_CONTRATO.md

Y dile a Daniel qué entendiste antes de modificar código.

## Cómo trabaja Daniel (aprendido en la sesión del prototipo)

- Haz solo lo que pide; no cambies otras partes del proyecto.
- Confirma antes de acciones que salen del Mac o tocan sus dispositivos: instalar en el iPhone o el
  reloj, subir a TestFlight, borrar targets, hacer commit.
- Si dices que algo funciona, que sea porque lo verificaste (build, ejecución, archivo). Di
  claramente qué no pudiste comprobar.
- Si te refieres a un acuerdo anterior y no lo encuentras en el repo o en los docs, pregunta; no lo
  adivines.
- Si llevas varios intentos sin avanzar, para y da una recomendación con una decisión clara, no una
  lista de opciones ni más pasos de lo mismo.
- Respuestas cortas y concretas. Los textos de la app en español.
- Su reloj es un Apple Watch Series 10 (42/46 mm): sin Action Button. Xcode usa Device Hub.
