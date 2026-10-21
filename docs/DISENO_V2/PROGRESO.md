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
- Voz: es el núcleo de la app y debe estar completa en v2, reutilizando el v2t existente (mismo VoiceRecorder/Interpreter/validación/setters de v1). Incluye mic grande para todo el hoyo, dictado por jugador al tocar su nombre, banner de lo entendido/aplicado, el mismo paso de revisión de v1 y "Deshacer" del último dictado (foto del hoyo en la capa v2, restaurada con los mismos setters; sin tocar MatchManager).
- Pendiente: insignia "VIGENTE" en Historial (mantener como texto o quitar).

## Paso 1 — Hoyo actual compartido (21-oct)
- v1: `currentHoleIndex` pasó de `@State` a `@AppStorage("currentHoleIndex")` (única excepción permitida) y `setupOnAppear` ya no lo recalcula al reaparecer; v2 lee la misma clave (`ContentViewV2`, con ‹ › provisionales).
- Cambio de comportamiento en v1: al abrir la app queda en el último hoyo visto (antes saltaba al primer hoyo incompleto). `cerrarRonda` y el cambio de hoyo de salida lo regresan a 0.
- 41 pruebas verdes; compila. Falta revisión de Daniel en el simulador (v1↔v2 en el hoyo 14).
