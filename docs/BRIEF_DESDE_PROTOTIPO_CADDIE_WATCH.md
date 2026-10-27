# Brief: llevar a Caddy_Score (viene de la sesión del prototipo "Caddie Watch")

27-oct-2026 · Daniel Olivares · Idioma: español

## 1. Objetivo

Implementar `docs/WATCH_EXPERIENCIA_MATCH_SPEC.md` en este proyecto (`~/Developer/Caddy_Score`, con el target `CaddieWatch Watch App`, `WatchShared/` y `docs/WATCH_VOZ_CONTRATO.md`). Un clic y una frase: lápiz, goma o pregunta. La tarjeta del reloj es la del iPhone a menor escala, y **nada se anota sin tocar Aceptar**.

## 2. Decisiones de Daniel (ya cerradas)

- Se actualiza al terminar el hoyo.
- No se depende de AirPods: nada de respuesta hablada obligatoria.
- "Deshaz" solo deshace la última anotación.
- El reloj **solo muestra lo dictado**.
- **La interpretación no cambia**: la hace el iPhone (alias, strokes, apuestas, unidades). El reloj graba, pinta la tarjeta recibida (`WatchCardDTO`) y manda órdenes (`WatchCommand`).
- Sin iPhone cerca: el reloj encola la frase y el hoyo queda "Pendiente de revisar".
- Botón del mic (propuesto, falta confirmar): botón grande en el inicio, complicación en la carátula y Double Tap con la app abierta. **El Series 10 no tiene Action Button.**

## 3. Plan por etapas (propuesto)

1. Leer lo que ya existe, sin tocar código: el contrato, `WATCH_APP_ENCARGO.md`, `WatchShared.swift`, `WatchModel.swift`, la vista del reloj y `V2/TarjetaV2.swift`.
2. Probar que este proyecto se instala en el reloj físico.
3. Tarjeta compartida con **Aceptar** (un solo componente en `WatchShared/`).
4. Preguntas en modo lectura (hoyo vs rival, strokes, unidades, leer hoyo, cómo voy).
5. Botón del micrófono y la complicación.

## 4. Lo que NO está verificado

- Que este proyecto se instale hoy en el reloj físico.
- Que la grabación con `AVAudioRecorder` funcione en el Series 10.
- De dónde sale el umbral de 0.80 de confianza (en el prototipo, "dudoso" salía de la lógica del intérprete, no de una confianza).
- No se leyeron el contrato ni el código del reloj de este proyecto.

## 5. Lo aprendido sobre instalar en el reloj

- Este Xcode usa **Device Hub** (Xcode → Open Developer Tool → Device Hub). Ya no existe Window → Devices and Simulators.
- Una compilación de desarrollo exige que el **UDID del reloj** esté en el perfil de firma. El reloj no lo muestra; el SEID no sirve. Solo se obtiene con Device Hub o Finder.
- En el prototipo, el Mac no veía el reloj (`devicectl` y `xctrace` solo listaban el iPhone) y su perfil listaba un solo dispositivo.
- El último build de este proyecto trae un perfil con **dos dispositivos**: el iPhone (`00008140-000A7DCC2E29401C`) y otro (`00008310-00072B1A227A601E`), probablemente el reloj. Sin confirmar.
- Equipo de desarrollo `RYLP3WV2WQ`; IDs `comDOG.Caddy-Score` y `comDOG.Caddy-Score.watchkitapp`.
- Alternativa sin UDID: **TestFlight**. Requiere crear la app en App Store Connect y subir un build.

## 6. Pendientes por decidir (de la spec)

- Columnas que caben con 5 jugadores en 42 y 46 mm. (El spec dice 45 mm, pero el Series 10 es de 42 y 46.) Idea: mostrar solo lo que cambia, resaltado ("Rob 5 → 6").
- Regla de oyes en par 3 y lista completa de unidades manuales.
- Qué botón abre el mic (ver sección 2).

## 7. Prototipo `~/Documents/Caddie Watch` (no tocar sin avisar)

Es un proyecto aparte, con un intérprete propio en el reloj que **duplica** lo que hace el iPhone. Tiene cambios **sin confirmar en git**: tarjeta con filas por jugador en la revisión (`ScoreRow`), el parser fonético (`PhoneticVariantsTests.swift`) y dos esquemas. Solo valdría la pena pasar acá las variantes fonéticas ("par" confundido con "bar" o "por") si el intérprete de este proyecto no las tiene, y el diseño de filas como referencia visual.

## 8. Referencias

- Canvas con 6 pantallas "Scorecard por voz – Apple Watch": sirve para la pantalla "Escuchando" y la paleta, **no para las columnas** (es anterior a la decisión "misma tarjeta que el iPhone").
- Paleta: `WATCH_APP_ENCARGO.md` §3 y `CaddieWatch Watch App/WatchStyle.swift`.
- Capturas del prototipo: `~/Documents/Caddie Watch/Docs/Screens`.
