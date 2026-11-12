# TODO y roadmap — Caddie Score

2026-11-11 · Daniel Olivares · Estado de lo pendiente, en el orden en que se mencionó. Nada de esto está construido.

## Distribución

- [ ] **Instalar la app en otras personas** (hoy solo TestFlight interno, grupo "DO & friends"). Definir: grupo externo de TestFlight (requiere revisión de Apple en el primer build), cuántas personas, y qué ven al abrir la app la primera vez.
- [ ] **Clave de OpenAI para otros (caso limitado).** Hoy cada instalación necesita `caddie.env` con `OPENAI_API_KEY` (Archivos ▸ Caddie Score); la app usa `gpt-4o-mini-transcribe` (voz) y `gpt-4o-mini` (interpretar y responder). Para otros no sirve pedir un archivo. Recomendación a decidir: un proxy pequeño con la clave en el servidor, un token por tester y tope diario de llamadas; la clave nunca va dentro de la app. Mientras tanto, sin clave la app funciona con captura manual (+/−) y sin dictado.

## Roadmap

- [ ] **GPS para marcar el campo** (trazar hoyos, tees y greens de un campo nuevo).
- [ ] **GPS: distancias por hoyo** (a green, frente, centro, fondo; hoy solo hay la distancia del tee elegido en la tarjeta).
- [ ] **Agente de reglas** (USGA y reglas locales): preguntar una regla y que conteste con la regla oficial y la local del campo. Punto de partida: `docs/REGLAS_LOCALES_CGM.md`.

## Apuestas y catálogo

- [ ] **Oyes acumulados como unidad manual (Oyes Acum):** se declara al final "pareja X–Y ganan dos" o "Fulana ganó dos", sin hoyo por hoyo, y espera que se agreguen a mano. Al usarlo en un match, el Oyes por hoyo de ese match queda inhibido. Falta confirmar con Daniel dónde se captura y cómo se activa por match.
- [ ] **Regla de Oyes:** con un solo puesto capturado hoy el match no cuenta (necesita puesto de los dos lados). Propuesta: quien tiene puesto le gana a quien no; si nadie tiene, queda "pendiente" y editable. No hay empates en par 3.
- [x] **Oyes Parejas:** decidido el 2026-11-11: la fila ya no sale en el Catálogo y, si las parejas juegan Oyes, se parte de como se reportaron en la tarjeta (mejor puesto de cada lado). El interruptor "Oyes" de cada pareja sigue. Sin commit ni build todavía.
- [ ] **Ajuste manual en dinero por match** (rival o pareja, con signo desde el punto de vista de Daniel, nota opcional).
- [ ] **Unidades editables al final** (hoy "Ver unidades" es solo lectura).
- [ ] **Unidades nuevas del catálogo visibles en todas las instalaciones**, como Zapato: las unidades que trae la app se agregan solas al catálogo guardado. Confirmar si además deben salir como opción dentro de la plantilla (tag) de cada match.

- [x] **Medal y Skins (2026-11-12):** apuestas del catálogo en unidades (nacen apagadas, "Vale" editable). Medal: golpes de los 18 hoyos menos strokes recibidos contra cada rival, gana el menor neto. Skins: por hoyo gana quien le gana en neto a todos (strokes entre cada dos jugadores = diferencia de sus strokes contra la base), el empate acumula, el que gana después se lleva todos; ventana `SkinsV2` con la tarjeta de netos. Sin commit ni build todavía.
- [ ] **El tag decide qué apuestas aplican** (Daniel, 2026-11-12): quitar las fichas por match de "Apuestas activas"; la plantilla dice qué apuestas del catálogo aplican a cada match (individual o pareja, igual). Incluye marcar Skins y Medal como activados en el tag. Toca `betSwitchesForIndividual/ForPair` y reescribe `BetSwitchesTests`.
- [ ] **Simplificar el Refresh de B9:** hoy 3 botones + texto + selector de quién lleva el Carry. Propuesta: un selector Ninguno · Carry · Ajuste 50 (excluyentes) y un interruptor Doble B9 combinable.
- [ ] **Estadísticas históricas:** en "Mi historial" mostrar para el match los pares, birdies, bogeys, etc. como números junto al promedio histórico, para ver si se mejoró.
- [ ] **Preguntas por voz (slang):** "dame el acumulado de putts hasta el hoyo X de estos jugadores" como una conversación nueva.

## Reloj

- [ ] **Cola sin conexión:** hoy abrir la app del reloj cancela los dictados en cola (`WatchModel.init`). Dejarlos, mostrar "pendiente de revisar" y un acuse "Hoyo N listo ✓" cuando el iPhone los resuelva.
- [ ] **Coordinación del hoyo:** el hoyo en juego es del iPhone; el reloj no puede cambiarlo ni pasa solo al siguiente tras Anotar. Decidir si avanza solo.
- [ ] **Navegación del reloj:** indicador fijo del hoyo, Digital Crown para pasar de hoyo, el resultado no se descarta al bajar la muñeca, cancelar "Interpretando…".
