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

- [ ] **Oyes acumulados como observación de campo:** declarar al final "pareja X–Y ganan dos" o "Fulana ganó dos" (cantidad de Oyes ganados), sin capturar hoyo por hoyo, y que cuente como apuesta.
- [ ] **Regla de Oyes:** con un solo puesto capturado hoy el match no cuenta (necesita puesto de los dos lados). Propuesta: quien tiene puesto le gana a quien no; si nadie tiene, queda "pendiente" y editable. No hay empates en par 3.
- [ ] **Oyes Parejas:** decidir si los Oyes dejan de contar en parejas (y sale la fila del Catálogo) o solo se oculta la fila. Falta la respuesta A/B de Daniel.
- [ ] **Ajuste manual en dinero por match** (rival o pareja, con signo desde el punto de vista de Daniel, nota opcional).
- [ ] **Unidades editables al final** (hoy "Ver unidades" es solo lectura).
- [ ] **Unidades nuevas del catálogo visibles en todas las instalaciones**, como Zapato: las unidades que trae la app se agregan solas al catálogo guardado. Confirmar si además deben salir como opción dentro de la plantilla (tag) de cada match.

## Reloj

- [ ] **Cola sin conexión:** hoy abrir la app del reloj cancela los dictados en cola (`WatchModel.init`). Dejarlos, mostrar "pendiente de revisar" y un acuse "Hoyo N listo ✓" cuando el iPhone los resuelva.
- [ ] **Coordinación del hoyo:** el hoyo en juego es del iPhone; el reloj no puede cambiarlo ni pasa solo al siguiente tras Anotar. Decidir si avanza solo.
- [ ] **Navegación del reloj:** indicador fijo del hoyo, Digital Crown para pasar de hoyo, el resultado no se descarta al bajar la muñeca, cancelar "Interpretando…".
