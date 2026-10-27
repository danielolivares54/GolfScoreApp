# Caddie Score — Experiencia del jugador durante el match (spec)

27-oct-2026 · Daniel Olivares · Versión viva: https://claude.ai/artifact/XrSLPiNaeySWLCzq8PRWYW

Durante el match el jugador actualiza o consulta la tarjeta con un clic y una frase. El reloj muestra la misma tarjeta que el input del iPhone, a escala del reloj, y el jugador acepta con un toque: lo que ve es exactamente lo que se anota. El setup y el cierre de ronda quedan fuera de este documento.

Documentos relacionados: `docs/WATCH_VOZ_CONTRATO.md`, `docs/WATCH_APP_ENCARGO.md`, `docs/DISENO_V2/REORG_VOICESHEET_V2.md`.

## Principios

- **Un clic, una frase.** Un botón en el reloj abre el mic; la misma frase sirve para anotar, corregir o preguntar. El sistema decide cuál es.
- **La misma tarjeta en las dos pantallas.** El reloj pinta el hoyo con el mismo orden de jugadores, columnas, abreviaturas y colores que el input del iPhone, solo más chico. El jugador no reaprende nada.
- **Ver y aceptar.** Lo dictado aparece en la tarjeta del reloj y un toque en Aceptar lo escribe. Nada se anota sin ese toque.
- **Lápiz y goma.** Corregir es dictar el dato nuevo sobre la tarjeta que se ve; borrar y "deshaz" son igual de rápidos.
- **Las preguntas se contestan con la tarjeta.** "¿Qué tengo en el hoyo 8 vs Rob?" abre el hoyo 8 de los dos en formato tarjeta; la voz lo resume en una frase.
- **Respuestas concretas.** Nombres y números; la explicación solo si se pide ("por qué").
- **El iPhone interpreta, el reloj muestra.** La lógica de alias, strokes y apuestas sigue en el iPhone. El +/− manual queda de respaldo porque la voz confunde "par" con "bar"/"por".

## El ciclo durante el match

```
[Un clic]  →  [Una frase]  ─┬─→ Lápiz    (escribe score, putts, oyes)   ─┐
 botón del     sin mirar    ├─→ Goma     (corrige, borra, deshaz)       ─┼─→ [Ve la tarjeta]
 reloj                      └─→ Pregunta (strokes, unidades, lee hoyo)  ─┘    igual que en iPhone
     ↑                                                                         Aceptar o Cerrar
     └──────────────────── siguiente frase, hoyo tras hoyo ─────────────────────────┘
```

Las tres ramas terminan igual: la tarjeta en el reloj (Aceptar si se escribe algo, Cerrar si es pregunta) y una frase hablada, listas para la siguiente frase.

## Lápiz, goma y pregunta

Cada frase termina en la tarjeta del reloj: si escribe algo, espera Aceptar; si es pregunta, se abre en modo lectura. Ejemplos con nombres de prueba:

| Gesto | El jugador dice | El reloj muestra (formato tarjeta) | Al tocar |
| --- | --- | --- | --- |
| Lápiz · hoyo completo | "Hoyo 10, yo cuatro, Rob cinco, oyes primero Rob" | Tarjeta del 10: Daniel 4, Rob 5, oyes 1° Rob; lo que falta en naranja | Aceptar: se escribe, háptico ✓ |
| Lápiz · lo que falta | "Rob dos putts" | La misma tarjeta con los putts de Rob agregados | Aceptar |
| Lápiz · unidad | "Yo sandy" | Sandy en la fila de Daniel | Aceptar |
| Goma · corregir | "Rob seis en el diez" | Tarjeta del 10 con Rob 5 → 6 | Aceptar |
| Goma · borrar | "Borra el sandy de Daniel" | Sandy tachado en la fila de Daniel | Aceptar |
| Goma · deshacer | "Deshaz" | La tarjeta como estaba antes | Aceptar |
| Pregunta · hoyo vs rival | "¿Qué tengo en el hoyo 8 vs Rob?" | Hoyo 8 de Daniel y Rob: gross, stroke, neto y quién ganó | Cerrar (solo lectura) |
| Pregunta · strokes | "¿Strokes con Rob?" | Los 18 hoyos con el punto de stroke, con signo a favor o en contra | Cerrar |
| Pregunta · unidades | "¿Qué unidades llevo?" | Unidad y hoyo, verde ganada y rojo perdida | Cerrar |
| Pregunta · leer tarjeta | "Lee el hoyo 8" | Tarjeta del 8 con todos los jugadores | Cerrar |
| Pregunta · cómo voy | "¿Cómo voy con Rob?" | Match, F9 y B9 contra Rob | Cerrar |

## Reglas de la tarjeta en el reloj

1. **Misma tarjeta, otra escala.** Un solo componente de tarjeta para iPhone y Watch: mismo orden de jugadores, abreviaturas y colores (verde gana o bajo par, rojo pierde o sobre par, naranja falta).
2. **Aceptar siempre visible abajo.** La Digital Crown solo desplaza; no confirma ni cambia valores.
3. **Lo dudoso se marca en la tarjeta** (dorado) y se redicta solo esa fila antes de aceptar.
4. **El hoyo por defecto es el actual.** Si la frase dice otro número, la tarjeta que aparece es la de ese hoyo y lo dice en el encabezado.
5. **Las preguntas abren la tarjeta en modo lectura:** sin Aceptar, solo Cerrar, y una frase hablada con el resumen.
6. **Sin iPhone cerca:** el reloj guarda la frase en cola y el hoyo queda "Pendiente de revisar".

Esto coincide con el contrato actual del reloj (`WATCH_VOZ_CONTRATO.md`): se acepta antes de anotar y lo que baja de 0.80 de confianza sale como dudoso.

## Fricciones detectadas y prioridades

La fricción más cara está en el hoyo, no en el setup ni en el cierre: se repite 18 veces.

| # | Fricción | Dónde | Propuesta | Prioridad |
| --- | --- | --- | --- | --- |
| 1 | La propuesta del reloj no se ve como la tarjeta del iPhone | Watch | Reusar el layout de la tarjeta del iPhone a escala del reloj | Alta |
| 2 | El reloj no responde preguntas de la tarjeta | Watch | Hoyo vs rival, strokes, unidades, leer hoyo, cómo voy | Alta |
| 3 | Las respuestas no se ven en formato tarjeta | Watch | La pregunta abre la tarjeta en modo lectura + frase hablada | Alta |
| 4 | La voz confunde "par" con "bar"/"por" | Dictado | Mantener +/− manual y aprender frases | Alta |
| 5 | En el iPhone la respuesta sale lejos del botón | iPhone · Dictar el hoyo | Reorganizar en 3 zonas (`REORG_VOICESHEET_V2.md`) | Media |
| 6 | Regla de oyes en par 3 sin definir | Apuestas | Decidir regla del ranking | Media |

## Pendientes por decidir

- [ ] ¿Qué botón abre el mic? Propuesta: botón grande en la pantalla de inicio + complicación en la carátula + Double Tap con la app abierta (el Series 10 no tiene Action Button).
- [ ] ¿Qué columnas caben a 45 mm con 5 jugadores: golpes y putts siempre, unidades como ícono?
- [ ] ¿Hasta cuándo vale "deshaz": solo la última anotación o cualquier hoyo?
- [ ] ¿La frase hablada sale por la bocina del reloj o por AirPods si están conectados?
- [ ] Regla de oyes en par 3 (ranking) y lista completa de unidades manuales.
