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
