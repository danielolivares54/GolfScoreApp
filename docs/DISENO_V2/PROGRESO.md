# PROGRESO — Vista v2

## P0 — marco y botón v1/v2 (hecho)
- `RootView` es dueño de UN solo `MatchManager` y lo pasa a `ContentView` (v1) y `ContentViewV2`; el botón `v2` (barra superior de v1) y `Vista v1` (en v2) cambian `@AppStorage("uiVersion")` (default `v1`).
- `ContentView` recibe el match por init y su carga inicial corre una vez por match (`MatchManager.didRunInitialSetup`); sin esto, cambiar de vista perdía oyes/eventos/notas (solo viven en memoria).
- Archivos nuevos en `V2/` (carpeta en la raíz, como `como/`): `CaddieStyleV2.swift` (copia exacta de docs), `ContentViewV2.swift` (marcador de solo lectura). Los tests excluyen `V2/*` (`EXCLUDED_SOURCE_FILE_NAMES`).
- Verificado: build + 13 pruebas del caso de estudio; simulador v1→v2→v1→v2 con la ronda demo: oyes (2 hoyos), scores (18/18) y total (+$1225) idénticos.
- Pendiente: al volver de v2 la tarjeta abre en el hoyo 1 / primer hoyo incompleto (el hoyo actual es `@State` de cada vista); se resuelve en P1 al compartir el hoyo actual.
