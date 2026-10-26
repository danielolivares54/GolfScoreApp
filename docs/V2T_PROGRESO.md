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

## Tres funciones de lectura: revisar, apuestas y acumulado (23-oct)
- **Revisar:** Unidades · Strokes · Este hoyo (cómo quedó el hoyo contra cada rival) · Qué falta.
- **Apuestas:** Vuelta · Presión · Match · F9 · B9, con su **conteo** (arriba / abajo), el valor de cada una y si está apagada en ese match.
- **Acumulado:** Cómo vamos (conteo primero, dinero después) · Dinero (total, luego individuales y parejas) · **Por qué** (explica cómo resultó: hoyos ganados y perdidos por nueve, vuelta, presiones, match, Carry/Ajuste, unidades, strokes y lo que suma).
- **Un hoyo contra el rival:** qué tiró cada uno, quién lleva stroke en ese hoyo (con el neto), si gana, pierde o empatan, y cuánto iba antes la vuelta y las presiones abiertas y cómo quedan ahora. Un hoyo, un grupo ("del 5 al 8", formato corto) o el actual; individual y parejas.
- Todo se puede preguntar hablando: el LLM solo clasifica la pregunta (tipo, jugador, oponente, hoyo, hasta, segmento); el texto sale siempre de lo anotado. Un tipo que no entiende contesta qué sí sabe responder.

## Aprender (23-oct)
- **Transcripción con tu contexto:** al mandar el audio se le pasa a Whisper un prompt con el vocabulario de golf, las unidades del catálogo, las frases y apodos aprendidos y, al final (lo que más pesa), los jugadores del Setup con su alias (`transcriptionPrompt`).
- **Frases de unidades:** una unidad que no está en el catálogo ("tripoteó") queda como duda con un menú "¿Qué unidad es…?"; al elegirla se anota y la frase se aprende (`VoiceSlangStore`: apodos de jugadores y frases de unidades); la próxima vez se resuelve sola.
- **Ejemplos tuyos para el LLM:** las últimas frases tuyas y la tarjeta final que quedó bien (primero las de hoyos que costaron más de una dictada) viajan en cada llamada como `ejemplos`, junto a los `apodos`, para calibrar tu jerga sin copiar datos.
- **Medirlo:** la hoja de voz muestra "N dictadas · X de Y hoyos salieron a la primera · N apodos y frases aprendidos".
- Sigue pendiente (fase aparte): exportar los pares audio + texto + tarjeta final para ajustar un modelo; antes hay que decidir si esos audios se pueden subir.

## Match Parejas ya no se apaga (23-oct)
- Causa de "las parejas definidas y con strokes no contaban": el interruptor **Match Parejas** del catálogo estaba apagado y apaga todas las parejas de golpe, contraponiéndose a la pareja base del Setup. El interruptor se eliminó: las parejas cuentan siempre que haya pareja base en el Setup (`isPairMatchEnabled` siempre verdadero; no aparece en el editor de unidades v2 ni en el catálogo v1) y un catálogo guardado con ese tag apagado se vuelve a encender solo (`BetDefinitionStore.ensurePairTagOn`).
- Para no jugar parejas basta no definir la pareja base; para quitar una apuesta de parejas, las fichas por match (Vuelta, Presión, Match, Carry, Ajuste 50, Oyes, Unidades).
- El aviso de parejas sin calcular se queda para dos casos: sin pareja base y scores faltantes en un hoyo.

## Contrastar la tarjeta por jugador y vuelta; respuestas breves (23-oct)
- **Contrastar** (`ContrastV2.swift`): hoja con la tarjeta de UN jugador por F9 / B9 / 18, hoyo por hoyo (golpes, putts, quién le da stroke, ✕ si se levantó), total de la vuelta, leer toda la vuelta o un hoyo en voz alta y corregir cada hoyo (misma hoja de corrección de la Tarjeta). Se abre con el ícono de la cabecera de Tarjeta y con el botón "Contrastar tarjeta" de la hoja de voz. Hablando: "del F9 dame los golpes y strokes de Rob", "los golpes de Daniel del hoyo 3 al 7" (tipo `tarjeta`).
- **Respuestas breves por defecto:** toda lectura es un resumen (conteo, dinero total, una línea por match/vuelta); el botón **Más detalle** o decir "con detalle / hoyo por hoyo / explícame" da el detalle completo (`detail` en `answer`, `detalle` en la consulta del LLM).

## Corregir desde lo que se revisa (23-oct)
- Bajo cada lectura del apuntador sale **Corregir**: abre la tarjeta del jugador y la vuelta de lo que se preguntó con el hoyo resaltado (`ContrastSheetV2`), o el hoyo de todos los jugadores (`HoleCorrectionSheetV2`) cuando no se dijo de quién; cada lápiz abre la hoja de corrección (score, putts, oyes, unidades). Dinero, presiones, strokes y explicaciones no tienen botón (no se corrigen ahí). Rutas en `VoiceHolePipeline.correctionRoute`.

## Reglas/Notas y cierre de estatus (23-oct)
- La pestaña **Nota** pasó a **Reglas/Notas**: además de la nota por jugador y hoyo, tiene un campo de **reglas locales** (texto libre, guardado en el dispositivo; aún no se interpreta).
- Barra: Tarjeta · Unidades · Mic · Reglas/Notas · Resultado.
- Ya existe el dictado por jugador y hoyo con edición (Contrastar / Corregir).
- **Siguiente mejora:** Daniel entregará un archivo con las reglas locales para anotarlas e interpretarlas (cómo afectan o se consultan).
- Pendientes abiertos: notificaciones del apuntador, capa Watch, exportar voice records, revalidar prompts del LLM en vivo, rotar la clave de OpenAI.
- Todo en `diseno/v2t`, sin subir.

## Estatus corto: "¿cómo voy contra Ricardo?" (23-oct)
- Decisión de Daniel: las reglas locales NO se conectan al apuntador todavía; primero se prueba qué contesta y con qué alcance. Las respuestas deben ser más cortas y como una película, no una foto: se pregunta sobre el último hoyo y se asume lo anterior.
- Nuevo tipo `estatus`: el último hoyo jugado de cada match (individual y parejas): golpes brutos de cada lado, quién ganó, quién recibe stroke (o "sin strokes") y cómo va la vuelta. Con un jugador nombrado, "cómo voy / cómo vamos" ya no cae en el resumen general: lo clasifica el LLM (`ReadbackIntentV2.detect(names:)`).
- La lectura breve de un hoyo contra el rival solo menciona "ventaja de X" cuando alguien tiene stroke en ese hoyo (si no, no dice nada); cuántos strokes recibe es otra pregunta.

## Botones de lectura: solo conteos (24-oct)
- **Vuelta, Presión, Match, F9, B9 y Cómo vamos** contestan solo con conteos: "Al hoyo 8, match: individuales contra Roberto 3 arriba; contra Ricardo 1 abajo. Parejas contrarias: … 2 abajo. Mejor contra Roberto, peor contra Ricardo." Si preguntan por un solo rival contesta uno, sin comparación. "Más detalle" da la lectura larga de antes (`scoreboardReadbackV2`).
- **Por qué** (breve): por match, hoyos ganados / perdidos / empatados, cuántos hoyos adelante o atrás y en cuáles hay stroke y de quién (`whyBriefV2`). El detalle con dinero y conceptos sigue en "Más detalle".
- **Cómo vamos / conteo** (24-oct): una línea por rival con los cuatro números: "contra Roberto: vuelta F9 2 arriba, 1 presión a favor, match 3 arriba, unidades 2 arriba" (o "sin presión", "sin unidades").
- **"Los demás", "todos", "el resto"** en una pregunta ya no se buscan como jugador: se toman como sin filtro (todos los matches), también en el prompt del LLM.

## Contrastar con stepper y estatus a un hoyo (24-oct)
- En **Contrastar tarjeta** cada fila ya no trae el altavoz (18 íconos): lleva **− / +** para subir o bajar los golpes del hoyo directo (conserva putts y 3P/4P) y el lápiz para el resto; "Leer F9/B9/18" queda arriba (`setGrossV2`).
- **"¿Cómo van Jorge y Roberto al hoyo 15?"** (tipo `estatus` con hoyo): una línea por match como si vieras la tarjeta en ese hoyo: golpes de cada uno, quién ganó, ventaja si hay, y vuelta, presión y match a ese hoyo. Individuales primero y parejas contrarias después.
- **Números con signo (24-oct):** las lecturas breves dan el dato completo, siempre desde el lado del usuario: "vuelta más 3, presión menos 1, match más 2, unidades cero" (más = va ganando, menos = va perdiendo). Ya no dicen arriba/abajo en el estatus, el marcador ni el "por qué" breve; el detalle largo sí conserva arriba/abajo (`signedWords`).

## Apuesta de putts con dinero (25-oct)
- Es una apuesta de **unidades**, solo individual (parejas no la llevan; eso se controla con el tag PUTTS del catálogo). En cada tramo gana quien tenga menos putts, el empate no paga y vale `puttsBetUnits` unidades al valor de unidad de ese rival. Entra en las unidades del match (`unitsPoints`/`unitsMoney`) y no depende del interruptor Unidades.
- **Solo se calcula con todos los datos**: los 9 hoyos del tramo (o 18) con putts de los dos; si falta uno, ese tramo no paga todavía.
- Alcances: F9, B9, 18 y **Vuelta = tres apuestas** (F9, B9 y total a 18). `MatchManager.puttsBetPoints`.

## Watch v1 (25-oct): dictar, tarjeta con lápiz y goma, Anotar
- Target `CaddieWatch Watch App` (embebido, `comDOG.Caddy-Score.watchkitapp`). El reloj graba el hoyo (m4a), lo manda al iPhone (`transferFile`) y pinta la tarjeta que recibe por `applicationContext`; no interpreta nada.
- iPhone: `WatchCardCoordinator` (borrador, lápiz = `edit`, goma = `clear`/`removeChip`, `apply`, `undo`; pruebas en `WatchCardCoordinatorTests`) y `WatchBridgeV2` (WatchConnectivity). Se arranca en `RootView`.
- Compartido: `WatchShared/WatchShared.swift` (tarjeta y órdenes), en los dos targets.
- Reglas: lo dudoso bloquea Anotar hasta tocar ✎; la corona solo desplaza (no aplica ni edita); Anotar es un botón; Deshacer sale tras anotar. Unidades y oyes salen como fichas con goma (sin lápiz todavía).
- Pendiente: probar en un reloj real, doble toque para Anotar, preguntas/lecturas en el reloj, cola sin iPhone.
- **Corrección tras probar en simulador (25-oct):** el puente del iPhone solo atendía mensajes del reloj *con* respuesta; WatchConnectivity descarta los demás, así que el iPhone nunca veía "dame el estado" ni las órdenes (Anotar, lápiz, goma). Ahora atiende las dos variantes. El reloj reintenta pedir el estado cada 4 s mientras no lo tenga, cancela audios viejos sin entregar, ignora un "procesando" guardado de antes de abrir y caduca a los 30 s si el iPhone no contesta. El iPhone cancela una dictada vieja si llega otra y no pasa de 45 s.

## Cómo vamos, directo (25-oct)
- La lectura breve de **Cómo vamos** y del conteo da el hoyo y la vuelta y, por jugador y pareja, el **resultado de cada concepto**: vuelta, **cada presión abierta con su propio valor**, carry (con su presión) y match, siempre desde el lado de quien pregunta (más = va ganando, menos = va perdiendo). Sin "Llevas N hoyos", unidades ni dinero: eso tiene sus botones y "Más detalle".
- Ejemplo (demo): "Roberto: vuelta más 4, presión más 2, carry más 3, presión del carry más 1, match más 6. Ricardo: vuelta menos 2, sin presión, match más 1. … pareja con Fernando contra Roberto y Ricardo: vuelta más 5, presión más 2, match más 11." Sin carry activo no se dice carry (`compactStandingsV2`).

## Todo breve por defecto (25-oct)
- Regla: toda lectura es breve; lo largo solo con "Más detalle". Nombres (no alias) y números con signo; sin dinero ni frases de relleno en lo breve.
- Etiqueta corta de cada match (`briefLabelV2`): "Roberto" o "con Fernando vs Roberto y Ricardo".
- Recortes: **nueve** ("Roberto: F9 más 2, B9 más 4, match más 6"), **presiones** ("B9 presión más 4 y más 1"), **strokes** (solo quien recibe y cuántos), **vuelta/presión/match** (sin "contra", sin "Mejor/peor"; "Parejas: …"), **hoyo y estatus** (sin encabezados largos), **por qué** (cuántos hoyos con stroke, no cuáles), **leer el hoyo** ("Hoyo 14, par 3: Daniel 3, Fernando 2, … Oyes 1 Fernando, 2 Roberto…").
- El detalle completo (dinero, listas de hoyos, antes/ahora) sigue en "Más detalle".
- **Instalación en el reloj (25-oct):** "unable to install" por versiones distintas: la app del reloj era 1.0 (1) y la del iPhone 1.0.2 (3). Una app de reloj embebida debe llevar la **misma versión y build** que la del iPhone; el target del reloj ahora usa MARKETING_VERSION 1.0.2 y CURRENT_PROJECT_VERSION 3. Si se sube la versión del iPhone, subir también la del reloj.
- **Ícono del reloj (25-oct):** la app del reloj no tenía ícono (catálogo vacío, sin `Assets.car` ni `CFBundleIcons`) y salía como un círculo gris en la app Watch del iPhone. Ahora usa el mismo de 1024 px que el iPhone (pelota con bandera CGM).

## Setup v2: agregar jugadores (25-oct)
- Con una app limpia (o sin match guardado) se siembra un match con los 5 jugadores de `match_meta.json`; con 5 jugadores el campo de nombre estaba desactivado y no abría el teclado. Ahora el campo siempre abre el teclado y, con 5, avisa debajo que hay que quitar uno.
- El directorio se ve sin teclear: fila **"Del directorio"** con los jugadores que aún no están en el match (los más usados primero); un toque agrega al jugador con sus strokes y su plantilla.
- **El usuario es siempre el jugador 1 (25-oct):** `yoAlias` es el primero de la lista, así que en Setup v2 el dueño de la app (USER_NAME del `caddie.env`, o el "yo" actual) no se quita (la fila dice "Tú"), siempre queda primero (`SetupDraftModel.ensureUserFirst`, se aplica al cargar) y no se puede agregar otra copia. La **pareja base no depende del lugar**: se elige en Parejas; la lista ya no dice "Pareja base 1/2" por posición, sino "Pareja base" para quien está elegido como base 1 o 2. Pruebas: `UserIsAlwaysPlayerOneTests`.

## Corregir por voz sin borrar lo demás; nombres no entendidos (25-oct)
- **Nombre no entendido = descartado.** Un nombre que no está en el grupo ni se parece a nadie ya no deja una fila suelta ni se puede asignar: se ignora y se avisa ("No entendí a «Chino»; no lo agregué."). La voz nunca toca el Setup (solo las pantallas de Setup agregan jugadores). Se aplica a scores, putts, "se levantó", corridas, oyes, unidades y notas. Los apodos ya enseñados siguen resolviéndose solos. En el reloj sale como aviso naranja (`notice`).
- **Corregir un hoyo solo cambia lo dictado:** cada celda, unidad o nota dictada se escribe aparte; los demás jugadores del hoyo (scores y putts) no se tocan. Los **oyes parciales** ya no borran el orden que estaba bien: solo se reemplaza si lo dictado cubre a todos los que ya tenían lugar; si no, se conserva el anterior y se avisa que falta el orden completo.
- Pruebas: `anUnknownNameIsDroppedAndNeverAddedToTheSetup`, `reEditingOnePlayerLeavesEveryoneElseUntouched`, `aPartialOyesDoesNotEraseTheOrderThatWasRight` y las del reloj.
