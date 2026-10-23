# v2t — dictado integral del hoyo (rama `diseno/v2t`)

## Hecho
- **Pipeline** (`V2/VoiceHolePipelineV2.swift`): una dictada con score, putts, orden de oyes, unidades y notas → borrador del hoyo → reporte "Entendí… / Revisa… / Falta…" → Anotar (con Deshacer del hoyo completo).
- **Lo que falta se pide**: jugadores sin score, putts, lugar de oyes (solo par 3 con Oyes activo). Se dicta solo lo que falta y se suma al borrador; lo más reciente gana en cada celda.
- **Unidades**: se aceptan las manuales del catálogo y también 3 Putt, 4 Putt y Hole Out (sin botón). Por ahora solo se reciben; si cuentan o no se decide después. Una unidad que no existe queda como duda.
- **Apodos**: un nombre que no está en el roster se reasigna con un toque y la app aprende el apodo (`VoiceSlangStore`, en el teléfono, y viaja al LLM como contexto).
- **Grabaciones para reentrenar** (`VoiceRecordStore`, `Documents/voice_records`): cada dictada guarda audio + texto; al anotar, quedan ligadas a la tarjeta final. Todo local; subirlas / reentrenar es una fase posterior.
- Pantalla: `V2/VoiceSheetV2.swift` (mic de la barra de la ronda). Pruebas: `VoiceHolePipelineTests` (13).
- Nota: el intérprete de v1 descarta "dan" y "yo" si no se dijo "Daniel"; en v2t lo dicho con nombre manda y el intérprete solo aporta "los demás", "todos" y bogey/birdie sin número.

## Pendiente
- Probar con voz real en el iPhone (Whisper + LLM; falta la clave de OpenAI en Info.plist).
- Setup por voz (nombres, strokes) — versión posterior.
- **Apuntador automático**: notificaciones de lo que la tarjeta ya tiene grabado y de lo que falta (la lectura a petición ya está hecha, ver abajo).
- Capa WatchConnectivity en el iPhone (contrato en `docs/WATCH_VOZ_CONTRATO.md`; ahí el contrato dice 1 dictada por hoyo, `propose`/`report` ya devuelven lo que el reloj necesita pintar) y target watchOS (se crea desde la UI de Xcode).

## Corridas de hoyos y "se levantó / perdió el hoyo" (23-oct)
- **Corrida**: "del hoyo 5 al 8 Roberto par, bogey, doble bogey, par y dos putts por hoyo" → un cambio por hoyo con el par de cada hoyo (par 3 + 0, par 5 + 1…). Un solo resultado se aplica a todos los hoyos; solo putts conserva los golpes que ya estaban. Si el número de resultados no coincide con el de hoyos, **pregunta** (no adivina). Admite vuelta (del 17 al 2).
- **Se levantó / perdió el hoyo / bola equivocada** (misma regla, individual y parejas): se le pone **un golpe más que el neto más alto de los demás** (el neto de cada quien con los strokes de su match) y **a él no se le aplica stroke en ese hoyo**: queda con una cruz ✕ en la Tarjeta (`CellOverride.lostHole`, guardado en `bet_config.json`), su neto es el más alto y pierde. El motivo ("Bola equivocada") queda de nota en el hoyo. Si faltan los scores de los demás, lo dice y no anota. Corregirle el score o Deshacer devuelve los strokes.
- Todo cuenta como un solo dictado: Deshacer restaura todos los hoyos tocados.

## El apuntador lee lo anotado, a petición (23-oct)
- En la hoja de voz: botones **Leer el hoyo**, **Qué falta** y **Cómo vamos**, o decirlo ("qué llevo", "léeme el hoyo", "cómo vamos", "qué falta"): se detecta en el teléfono, sin LLM y sin gastar una dictada. Lee con voz es-MX y también lo muestra en pantalla; se puede detener.
- Hoyo: scores con nombres, putts, "se levantó", oyes, unidades, notas y lo que falta. Ronda: hoyos completos y dinero con cada quien y en total.
- Todo sale de lo ya anotado en MatchManager (`CardReadbackV2.swift`, pruebas en `CardReadbackTests`).

## Preguntas sobre lo anotado (23-oct)
- Se pregunta hablando y se responde con lo anotado: "¿qué hizo Roberto en el 5?", "¿cuántos golpes lleva Fernando?", "¿qué oyes ha ganado Daniel?", "¿dónde hizo unidades Ricardo y cuáles?", "¿qué resultados hay en el F9 / B9?", "¿qué presiones hay abiertas en el B9?", "¿con cuántos strokes?".
- **Cómo se resuelve:** el LLM solo clasifica la pregunta (`consulta`: tipo, jugador, hoyo, segmento) en la misma llamada que ya se hace al dictar; la respuesta NO la escribe el LLM: sale de MatchManager (`queryAnswerV2`, `nineAnswerV2`), igual que lo que ve la Tarjeta y Resultados. Una pregunta nunca toca la tarjeta. "Qué llevo / cómo vamos / qué falta" se detectan en el teléfono, sin LLM.
- Los nueves dicen: cómo vas (arriba/abajo, tras cuántos hoyos), presiones abiertas con su valor, strokes del match y si Carry / Ajuste 50 / Doble B9 están activos.
