# PROGRESO — Vista v2

## P0 — marco y botón v1/v2 (hecho)
- `RootView` es dueño de UN solo `MatchManager` y lo pasa a `ContentView` (v1) y `ContentViewV2`; el botón `v2` (barra superior de v1) y `Vista v1` (en v2) cambian `@AppStorage("uiVersion")` (default `v1`).
- `ContentView` recibe el match por init y su carga inicial corre una vez por match (`MatchManager.didRunInitialSetup`); sin esto, cambiar de vista perdía oyes/eventos/notas (solo viven en memoria).
- Archivos nuevos en `V2/` (carpeta en la raíz, como `como/`): `CaddieStyleV2.swift` (copia exacta de docs), `ContentViewV2.swift` (marcador de solo lectura). Los tests excluyen `V2/*` (`EXCLUDED_SOURCE_FILE_NAMES`).
- Verificado: build + 13 pruebas del caso de estudio; simulador v1→v2→v1→v2 con la ronda demo: oyes (2 hoyos), scores (18/18) y total (+$1225) idénticos.
- Pendiente: al volver de v2 la tarjeta abre en el hoyo 1 / primer hoyo incompleto (el hoyo actual es `@State` de cada vista); se resuelve en P4 (hoyo actual compartido entre v1 y v2).

## P1 — ResultadoV2 (hecho)
- `V2/MatchManager+V2.swift`: lectura pura; `resultadoRowsV2()` llama las mismas funciones que `ResultsSheetView.resumenRows` (v1). `V2/ResultadoV2.swift`: total, tarjeta Individual y tarjeta Parejas (golpes en palabras, hasta 3 parejas); tocar una fila abre `MatchZoomView` (v1). Se abre con el botón "Resultado" del marcador `ContentViewV2` (provisional hasta `RoundBarV2`).
- Pruebas: `DemoFixture` + `ResultadoV2DataTests` (7); suma 20 pruebas verdes. Simulador: los 7 matches y el total (+$1225) son idénticos a la tabla de v1.
- Decisiones/diferencias: sin switch de pareja ni "no se juega hoy" (no existen en v1); la columna Oyes va dentro de Unid (como en v1); F9/B9 con flechas ↑/↓ en vez de +/−.
- Presiones y Carry (pedido de Daniel): cada fila lleva una línea con etiquetas bajo las columnas — "F9 presiones +3 −1 · B9 presiones +2 · Carry +$100" — con los mismos valores que la tabla de la v1 (`individual/pairF9Presion`, `…B9Presion`, `carryActive/carryMoney` del wallet). Verificado en simulador y fijado en 2 pruebas (22 verdes).
- Pendiente: tocar Unid no abre `UnitLogDetailView` todavía; "‹ Hoyo N" es "Volver" hasta compartir el hoyo actual (P4).

## Decisiones de Daniel (P1)
- Presiones y Carry se muestran como en v1 (hecho, línea con etiquetas bajo cada match).
- Nombres de pareja: sin "+" — se unen con guion ("ROB – RIC", "con X – Y"); en pantalla v2 nunca se usa "+" para unir nombres.
- Oyes: se quedan dentro de Unid (son unidades; se capturan en las pantallas de entrada), sin columna aparte.
- Marcas de golpes (círculos/puntos): se conservan como están; de la v2 solo se toma el tamaño definido (se aplica en P2, TarjetaV2).

## P2 — TarjetaV2 (hecho)
- `V2/MatchManager+V2.swift` (`tarjetaNinesV2()`, solo lectura) y `V2/TarjetaV2.swift`: tabla por nueve JUGADO (con salida en 10: `F9 · 10–18` / `B9 · 1–9`), marcas golf estándar con los tamaños de la v2 (marca 32 pt, filas 52 pt), HCP con contorno, cuadro dorado para evento/oye, fila de cierre oscura con par y golpes por nueve y fila "Total 18". Se abre con el botón "Tarjeta" del marcador `ContentViewV2`.
- Decisiones de Daniel: opción B (marcas del diseño) también para oyes y birdie; la columna de yo se queda como la v1 — los puntos de golpe solo salen en rivales que reciben de yo (regla v1: `distributedStrokes(total: strokesVsBase)`), nunca en la columna de yo.
- Pruebas: `TarjetaV2DataTests` (9); 31 verdes. Vista previa renderizada (salida 1 y salida 10 con FER recibiendo 3½).
- Pendiente: fila del hoyo actual en verde y "‹ Hoyo N" (necesitan el hoyo actual compartido, P4); el Golpes de v1 muestra el mismo número de columnas pero sin marcas golf; no se probó con Dynamic Type grande ni modo oscuro.

## Revisión de diseño — pantalla 1: Tarjeta (decisión de Daniel, 21-oct)
- Se quitan los contornos de las marcas (círculos/cuadros/dobles): se veía saturada. El resultado vs par lo dice el COLOR del número (verde bajo par, tinta par, rojo sobre par); se conservan el punto azul de golpe y un punto REDONDO dorado para unidad/oye (antes cuadro). `ScoreMarkV2(outlined:)` conserva el dibujo estándar, apagado por defecto.
- Leyenda: "bajo par / par / sobre par" y los dos puntos. Fila de cierre dibujada con rectángulo (esquinas redondas solo en la tarjeta).

## P1 (ampliación) — Detalle de match a pantalla completa (paridad con la v1)
- Pedido de Daniel: que la v2 use TODOS los datos de la v1 y que Carry / Ajuste 50 / Doble B9 sean grandes. Inventario de la v1 (`ResultsSheetView.individualCard/pairCard/matchCard/buildResumen`): encabezado con Tag, línea de condiciones, tabla F9 / B9 (×2) / Match / Carry / Ajuste 50 / Unidades con fichas, dinero y detalle, línea de strokes, Total con quién paga a quién, estado del refresh de B9, botones Carry / Ajuste 50 / Doble B9 (11 pt, se desactivan con F9 empatado), selector de quién lleva el Carry en pareja, enlaces a hoyo por hoyo, tarjeta Carry y log de unidades.
- `V2/MatchDetailDataV2.swift` (mismas funciones que la v1: `matchResumenV2`, `refreshStateV2`, `strokesSummaryV2`, `unitLog*V2`, y las acciones `toggleCarryV2 / toggleAdjust50V2 / toggleDoublePressV2`) y `V2/MatchDetailV2.swift` (pantalla completa; botones de 80 pt; filas de 56 pt+; toque en la fila despliega el detalle y su enlace). Al tocar una fila de Resultado v2 se abre este detalle (antes abría solo el hoyo por hoyo).
- Verificado: 41 pruebas verdes (total de los 7 matches = su línea de la billetera; tabla de ROB y de la pareja; textos de estado; acciones). Simulador: Ajuste 50 sustituye a Carry, Carry lo restituye, Doble B9 apagado → "B9" y total −$100.
- Diferencia con la v1: el selector de quién lleva el Carry se ve siempre que hay más de un candidato (la v1 solo lo mostraba con el Carry ya activo) y, si el Carry ya está activo, elegir otro compañero lo aplica al momento.
- Pendiente: el lienzo (canvas) con las imágenes de referencia no está en el repo (`docs/DISENO_V2/screens/` no existe) — la v2 se construye desde el texto de DESIGN_SPEC.md y las decisiones de Daniel; probar en simulador el enlace "Ver F9 hoyo por hoyo" y el selector de pareja (cubiertos por pruebas y vista previa).

## Tarjeta — nombres de jugadores (pedido de Daniel, 21-oct)
- Línea fija bajo el selector de nueve: "DAN Daniel · FER Fernando · …" (código en negritas + nombre), siempre visible; las columnas siguen con el código porque con 5 jugadores no caben nombres a 13 pt.
- GAP_ANALISIS.md: MatchDetailV2 marcado ✅ (pendiente de tu revisión); quedan abiertos Putts en Tarjeta, fila del hoyo actual y tocar una celda.

## Decisiones de Daniel (21-oct, gap analysis)
- Botón "demo": oculto en v2 (solo existe en v1).
- Putts en TarjetaV2: con un toggle "Putts" (apagado = golpes; encendido = putts en las mismas celdas + total de putts por nueve).
- (REEMPLAZADA, ver "Voz fuera de v2" abajo) Voz: es el núcleo de la app y debe estar completa en v2, reutilizando el v2t existente (mismo VoiceRecorder/Interpreter/validación/setters de v1). Incluye mic grande para todo el hoyo, dictado por jugador al tocar su nombre, banner de lo entendido/aplicado, el mismo paso de revisión de v1 y "Deshacer" del último dictado (foto del hoyo en la capa v2, restaurada con los mismos setters; sin tocar MatchManager).
- Pendiente: insignia "VIGENTE" en Historial (mantener como texto o quitar).

## Paso 1 — Hoyo actual compartido (21-oct)
- v1: `currentHoleIndex` pasó de `@State` a `@AppStorage("currentHoleIndex")` (única excepción permitida) y `setupOnAppear` ya no lo recalcula al reaparecer; v2 lee la misma clave (`ContentViewV2`, con ‹ › provisionales).
- Cambio de comportamiento en v1: al abrir la app queda en el último hoyo visto (antes saltaba al primer hoyo incompleto). `cerrarRonda` y el cambio de hoyo de salida lo regresan a 0.
- 41 pruebas verdes; compila. Falta revisión de Daniel en el simulador (v1↔v2 en el hoyo 14).

## Voz fuera de v2 (decisión de Daniel, 21-oct)
- Reemplaza la decisión anterior de voz en v2: la voz se construirá como **v2t** compartido iPhone + Watch, no dentro de la Vista v2. PLAN_PASOS.md: Paso 3 retirado; HoleScreenV2 y TarjetaV2 dejan solo ganchos vacíos. v1 conserva su voz intacta.
- Hoyo actual (Paso 1): se mantiene guardado y al abrir la app queda en el último hoyo visto.

## Paso 2 — HoleScreenV2 (21-oct)
- `V2/HoleScreenV2.swift`: barra superior (semáforo de auditoría, Setup, Historial, 🏁 con el mismo diálogo, Vista v1), tarjeta verde del hoyo con ‹ ›, tira de estado por rival/pareja, filas de jugador (−/score/+, putts según R8, strokes en palabras), Oyes en par 3, "Hoyo N listo →", `RoundBarV2` (Evento, Mic y Nota son ganchos vacíos hasta el Paso 4 y v2t).
- Cambios en v1 (movimientos literales para compartir lógica): `cerrarRonda` y la carga inicial pasaron de `ContentView` a `MatchManager.closeRound()` y `MatchManager.loadInitialMatchState()` (la app puede abrir primero en v2). Mismo orden de llamadas.
- Compila, 41 pruebas verdes, vista previa en `~/Desktop/CaddyScore_V2_Screens/P3_01_HoleScreen_demo.png`. Falta: prueba en simulador capturando la misma ronda en v1 y v2.

## Paso 4 — EventSheetV2 y NoteSheetV2 (21-oct)
- Pedido de Daniel: el Oyes debe aparecer en el hoyo como en la v1 (distintivo "Oyes"), y poder agregar eventos y notas.
- `HoleScreenV2`: tarjeta "Eventos y notas del hoyo" (arriba de los jugadores) con "DAN Oyes 1º", los eventos de unidad (manuales y calculados, sin BIRD) y las notas. `Evento` y `Nota` de la barra abren `EventSheetV2` (fichas del catálogo manual, agregar/quitar con upsert/removeUnitEvent) y `NoteSheetV2` (upsert "NOTA" / borra si queda vacía). Mismas llamadas que la v1.
- Compila, 41 pruebas verdes; vistas previas P3_02 a P3_04. Falta revisión en simulador (agregar/quitar en v2 y verlo en v1).
- Decisión de Daniel (21-oct): "Evento" pasa a llamarse **Unidades**. 3 Putt y Hole Out no son botones especiales: son unidades del catálogo como Sandy par, Green en regulación o Birdie en el 18; cada una se define por su modo de captura y se activa en el catálogo de apuestas. La hoja lista las unidades manuales activas, sin grupos ni tags fijos.

## Paso 5 — TarjetaV2: putts, hoyo actual, tocar celda (21-oct)
- Interruptor "Putts" (apagado = golpes con sus marcas; encendido = putts en las mismas celdas, total de putts por nueve y "Putts 18"). Datos: `TarjetaCellV2.putts` y `TarjetaNineV2.puttsTotals` (solo putts que ya registra el match, regla R8).
- Fila del hoyo actual en verde claro (misma clave `currentHoleIndex` que v1 y la pantalla de captura). Tocar una celda lleva a ese hoyo en `HoleScreenV2` y cierra la Tarjeta; el dictado a ese jugador queda para v2t.
- 45 pruebas verdes (+4 de putts); vista previa P3_05. Falta revisión en simulador.

## Paso 6 — ResultadoV2: pendientes (21-oct)
- Tocar la columna Unid abre el log de unidades de ese match (`UnitLogDetailView` de v1, los 18 hoyos). La fila ya no es un solo botón: nombre + F9/B9 y $ abren el detalle del match, Unid abre el log (sin botones anidados).
- "‹ Volver" ahora dice "‹ Hoyo N" (hoyo actual compartido) y regresa a la pantalla de captura.
- Compila; pruebas verdes. Falta revisión en simulador.

## Paso 7 — AuditV2 (21-oct)
- `V2/AuditV2.swift`: lista F9/B9 por hoyo con las celdas de cada jugador (score con marca, neto "→", putts, advertencias naranja/rojo), capítulo "Oyes y unidades" y hoja de corrección (Score, Putts, puesto de Oye en par 3, unidades activas). Guardado idéntico al de la v1: `applyHoleEntry`, restaurar 3P/4P y espejo a `ScoreManager`. El semáforo de `HoleScreenV2` abre `AuditV2`.
- Igual que en la v1, el ícono ✓ del hoyo aparece aunque falten putts (el borde naranja y "—p" avisan).
- Compila, vista previa P3_07. Falta revisión en simulador (corregir un hoyo en v2 y verlo en v1).

## Preparación del Paso 8 (21-oct)
- Decisión de Daniel: mover el guardado del Setup a `MatchManager` para que la activación por voz del Setup (fase con el Watch / v2t) use la misma lógica.
- `MatchManager.applySetupDraft`, `applyCourseAndStartHole` y `setupLanes` (movidos tal cual desde `GuidedSetupView`; la v1 ahora los llama). 4 pruebas nuevas en `SetupDraftTests` (guardar el mismo borrador no cambia nada, cambiar salida resetea Carry, cambiar strokes, carriles). 49 pruebas verdes.
- Decisión de Daniel: **editar el catálogo ("tag") queda como tarea pendiente para terminar las pantallas** → Paso 11 en PLAN_PASOS.md.

## Paso 8 — SetupV2 (21-oct)
- `V2/SetupV2.swift`: 3 pasos (Campo y hoyo de salida · Oponentes con strokes y apuesta por rival · Parejas con pareja base, carriles y apuesta de parejas). Strokes en palabras con los hoyos donde caen ("DAN recibe 8 · hoyos …"), controles grandes, ½. Log, Directorio y Apuestas abren las vistas de la v1. El engranaje de `HoleScreenV2` abre `SetupV2`.
- Lógica compartida (no duplicada en la vista): `SetupDraftModel` (estado y reglas del Setup), `MatchManager.applySetupDraft` / `applyCourseAndStartHole` / `setupLanes` / `setupAliases` / `strokeHolesText`. 55 pruebas verdes (+6 del modelo).
- Observación: en los carriles de pareja, quien "lleva" (strokeCarrier) es quien recibe los strokes (los puntos van en su columna); la v1 lo rotula "Da strokes". La v2 dice "Quién lleva los strokes". CONFIRMADO por Daniel (21-oct): en el Setup de parejas se define quién lleva los strokes; solo uno de la pareja los recibe y se puede reasignar al otro si hubo error.
- Falta revisión en simulador: cambiar hoyo de salida / strokes en v2 y ver el efecto en v1.

## Paso 9 — HistorialV2 y MyHistoryV2 (21-oct)
- Decisión de Daniel: sin insignia "VIGENTE" ni cuadro beige; línea azul "DAN recibe 8 → próximo: recibe 7" (el "próximo" solo en la ronda más reciente contra cada rival).
- `V2/HistorialV2.swift`: tarjeta por ronda (fecha · campo, hoyo de salida, total) y por rival: dinero, F9/B9 con flechas, resultado del match en palabras y strokes de esa ronda; filtro por rival; acceso a estadísticas. `V2/MyHistoryV2.swift`: histograma, golpes y putts (Prom. / Este match), promedio vs par por tipo de hoyo, impacto del stroke, oyes y dinero.
- Las fórmulas de estadísticas se movieron tal cual de `MyHistoryView` a `MyHistoryData` (v1 y v2 las comparten); 6 pruebas nuevas con una ronda cerrada sintética (`MyHistoryDataTests`). 61 pruebas verdes. El Historial de `HoleScreenV2` y el Log del `SetupV2` ya abren `HistorialV2`.
- No incluido: la etiqueta "En curso" de la spec (el historial solo lee rondas cerradas).

## Pasos 10 y 11 + Historial separado (21-oct)
- **Historial:** individuales y parejas separados en cada ronda (subtotal de cada grupo; el total de la ronda es la suma; con un rival filtrado solo cuentan sus líneas). Las parejas muestran "con FER / RIC – ANS", resultado del match y dinero (F9/B9 solo existen para individuales).
- **Paso 10:** las pantallas secundarias ya se abren desde la v2: log de unidades (Resultado y detalle del match), tarjeta Carry (detalle), Apuestas y Directorio (Setup). Se rediseñan solo si Daniel lo pide.
- **Paso 11 — `V2/CatalogoV2.swift`:** editor del catálogo (interruptor por unidad, "Vale" con − y +, alcance de la apuesta de putts, "Nueva" unidad manual individual, renombrar y borrar las creadas). Se abre desde la hoja Unidades y desde el Setup (botón Catálogo). Cada cambio se aplica al match en curso al instante.
- **Lógica (esto sí cambia reglas, a pedido de Daniel):** `MatchManager` ahora respeta el catálogo: Oyes / Oyes Parejas / Match Parejas apagados no cuentan (`isOyesEnabled`, `isOyesPairEnabled`, `isPairMatchEnabled`, `activeLanes`); el "Vale" de Oyes se usa; una unidad manual apagada no cuenta y conserva sus eventos (`isUnitCodeActive`). Por defecto todo está activo, así que sin tocar el catálogo nada cambia. `BetDefinitionStore`: `isBuiltIn`, `rename`, `removeCustom`.
- 68 pruebas verdes (+7 en `CatalogGatingTests`). Falta revisión en simulador.
- Decisión de Daniel (21-oct): las unidades de parejas capturables se ELIMINAN del pendiente (el tag se define solo). Siguen pendientes de decidir (CLEANING.md): Carry duplicado en Resultado y modo de captura "por input".

## Splash nuevo y Unidades sin 3 Putt / Hole Out (21-oct)
- La carátula usa el logo nuevo (`CaddieSplashMarkV2`, `V2/SplashMarkV2.swift`, dibujado con SwiftUI Canvas): pelota con hoyuelos y "CGM", hoyo y bandera. Se quitaron las formas del logo anterior de `Caddy_ScoreApp.swift`.
- La hoja Unidades de la v2 ya no muestra botones de 3 Putt, 4 Putt ni Hole Out (decisión de Daniel); siguen en el catálogo y el 3 Putt se marca solo al anotar putts.

## Quick fix Historial v1 (23-oct)
- El Historial de la v1 (que sigue abriéndose desde la ficha del Directorio, el Setup de la v1 y la pantalla de la v1) ya no muestra "Vuelta +0 · Match +0" ni la insignia "VIGENTE": solo "Match ganado / perdido / empatado". La línea "Próximo match: N strokes" se conserva en la ronda más reciente de cada rival. `HistorialV2` ya estaba así.
- Propuestas de Daniel pendientes de decidir (ver la conversación): acumulado en el Directorio, estadísticas con promedio y desviación estándar + porcentajes de "este match", y dinero acumulado en lugar de oyes ganados/perdidos.
