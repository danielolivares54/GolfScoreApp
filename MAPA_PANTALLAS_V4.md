# Mapa de Pantallas — Caddy Score (V4)

Reemplaza `PANTALLAS_MEJORA_V2.md` (obsoleto, usaba archivo:línea — las líneas cambian cada vez
que se edita una pantalla) y `SET_PANTALLAS_UI_V3.md` (vacío, nunca se llenó).

**Convención de este documento: identificar pantallas por nombre de struct, no por línea.**
Los structs casi no cambian de nombre aunque se reescriba su contenido — si se necesita la línea
exacta, se busca con grep en el momento (`grep -n "struct NombreView"`), es barato y siempre
está actualizado. Mantener esto al día: cuando se agregue/quite una pantalla o se cambie a qué
lleva un botón, actualizar este archivo en el mismo cambio.

Fecha: 2026-10-02.

---

## 1. Núcleo activo (alcanzable desde la app)

### `ContentView` — home / tarjeta viva de captura
Archivo: `ContentView.swift`. Es la pantalla raíz; todo lo demás se abre como `.sheet` desde aquí.

**Top bar** (`topBar`):
- Chip "Sale en H{n}" — informativo, no navega.
- 🟢/🟠/🔴 circular (semáforo de audit) → abre **`HoleAuditView`**.
- "$" circular → abre **`BetSetupSheet`**.
- ⚙ circular → abre **`GuidedSetupView`**.
- 🏁 `flag.checkered` → dispara `showCerrarRondaConfirm` (confirmationDialog inline, no abre pantalla nueva) → `cerrarRonda()`.

**Tab bar inferior** (`bottomBar`):
- Lápiz + mic ("Scorecard") → cierra todos los sheets, vuelve a `ContentView` (captura por voz inline, `editablePlayerGrid`).
- Grid icon ("Tarjeta") → abre **`TarjetaSheetView`** con `initialMode: .golpes`.
- `doc.plaintext` ("Resultado") → abre **`TarjetaSheetView`** con `initialMode: .resultado`.

**Dentro del body** (captura inline, sin pantalla nueva):
- Tap en avatar de jugador (`editablePlayerGrid`) → inicia dictado inline (mic bar abajo, `VoiceRecorder`, congelado).
- Botón "demo" (dentro de `legend`, texto chico) → **destructivo**: llama `seedDemoRound()`, reemplaza jugadores/scores actuales por una ronda de prueba fija (DAN/ANS/CAR/PED). No tocar sin avisar al usuario.

---

### `TarjetaSheetView` — contenedor de Golpes/Resultado
Archivo: `ContentView.swift`. Dos modos (`CardViewMode`): `.golpes` / `.resultado`, alternables con
un picker interno. En modo `.resultado` embebe **`ResultsSheetView`** (`embedded: true`).

---

### `ResultsSheetView` — selector unificado + tarjeta de match
Archivo: `ContentView.swift`. Vive embebida en `TarjetaSheetView` o standalone.

- Selector horizontal: círculos (rivales individuales) + cápsulas "pareja" (lanes), mezclados en
  una sola fila (hasta `jugadores-1 + lanes` botones). Cada botón selecciona un `MatchSelection`
  (`.individual(alias)` / `.pair(laneId)`) y despliega solo la tarjeta de ese match.
- `individualCard`/`pairCard` → `matchCard` (tarjeta compacta: título, F9/B9 con vuelta+presión,
  dinero V/P/C/M/U).
  - Tap en el header de la tarjeta, o en el box F9, o en el box B9 → abre **`MatchZoomView`**
    (con `initialSegment` = el segmento tocado, o el "actual" si fue el header).
  - Tap en el chip "U" del desglose de dinero → abre **`UnitLogDetailView`**.
- `scorecardStrip` — tira "GOLPES" horizontal (18 hoyos + subtotal OUT/IN), tap en una celda o en
  el número de hoyo → expande `holeDetailCard` debajo (inline, no sheet nuevo).
  - Tap en un jugador dentro de `holeDetailCard` → `correctionRequest` + `dismiss()` → vuelve a
    `ContentView`, que navega a ese hoyo y arranca dictado inline (mismo mecanismo que el tap de
    avatar en `editablePlayerGrid`).

---

### `MatchZoomView` — historial hoyo por hoyo de un match
Archivo: `ContentView.swift`. Full-screen sheet. Picker F9/B9 propio (`initialSegment` lo preselecciona).
Tabla: H+Par+HCP | jugador(es) | jugador(es) | Res | Acum, termina en fila "Subtotal {segmento}".
Círculos alrededor del score bruto = evento de unidad de ese jugador ese hoyo (no una columna aparte).

---

### `UnitLogDetailView` — detalle de unidades de un match
Archivo: `MoneyTrackerView.swift` (el struct vive ahí aunque `MoneyTrackerView` en sí está muerto).
Lista de una línea por evento: "H6 **DAN** gana unidad (+1) · Birdie vs FER".

---

### `GuidedSetupView` — configuración del match
Archivo: `GuidedSetupView.swift`. 4 pasos: Campo+Hoyo salida → Oponentes (jugadores+strokes) →
Parejas (+strokes de pareja) → Apuestas (catálogo, unidades calculadas vs manuales).

### `BetSetupSheet` — ajuste rápido de apuestas mid-ronda
Archivo: `BetCatalog.swift`. Mismo `selectedBetIds` que `GuidedSetupView.apuestasStep` (antes
tenían modelos separados y se desincronizaban — ver `CAMBIOS_CADDIE_v2.md`).

### `HoleAuditView` — "Corrección · Tarjeta"
Archivo: `HoleAuditView.swift`. Lista los hoyos con datos (ventana F9 o B9 según dónde haya score
real, no un cálculo fijo desde `startHole` — bug corregido 2026-10-02). Tap en una celda → abre
`HoleCorrectionSheet` (definida en el mismo archivo) para corregir score/putts/Oye de ese hoyo.

### `GuidedCaptureView` — captura manual con steppers (sin voz)
Archivo: `GuidedCaptureView.swift`. **Solo alcanzable vía Siri/App Intent** (notificación
`.openCaddyRecorder` o flag `pendingOpenRecorder` en `UserDefaults`) — no hay botón directo en la
UI para abrirla. Útil para probar en simulador sin micrófono real si se dispara manualmente.

### `RescueCaptureView` → `FuzzyReviewView`
Archivos: `RescueCaptureView.swift` / `FuzzyReviewView.swift`. Sheet controlado por `showRescue`;
no se identificó un botón visible que lo dispare en esta revisión — pendiente de ubicar si se
necesita.

---

## 2. Código muerto (definido pero nunca instanciado)

Verificado por grep de `NombreView(` en todo `Caddy_Score/Caddy_Score/` — ninguno de estos
aparece siendo llamado desde otra parte:

- `CoursePickerView`, `StartHolePickerView` (`CoursePickerView.swift`)
- `IntentTestView` (`IntentTestView.swift`) — panel de prueba con steppers para simular un
  `GolfScoreRecord` sin Siri; útil si algún día se cablea un botón de debug.
- `ScorecardView` / `CardView` (`ScorecardView.swift`) — par huérfano completo.
- `MoneyTrackerView` (`MoneyTrackerView.swift`) — eliminado del flujo real (ver
  `project_manual_refactor_ui` en memoria), pero el archivo sigue vivo porque adentro está
  `UnitLogDetailView`, que sí se usa.
- `SetupWizardView` (`SetupWizardView.swift`) — y por lo tanto `MatchSummaryView`
  (`MatchSummaryView.swift`), que solo se llama desde ahí.

No borrar sin confirmar — puede haber trabajo a medias o planes de retomarlos.

---

## 3. Diagrama de flujo (resumen)

```
ContentView (home)
 ├─ 🟢/🟠/🔴 audit ──────────────→ HoleAuditView ──(tap celda)──→ HoleCorrectionSheet
 ├─ $ ───────────────────────────→ BetSetupSheet
 ├─ ⚙ ───────────────────────────→ GuidedSetupView
 ├─ 🏁 ──────────────────────────→ (confirmationDialog inline) → cerrarRonda()
 ├─ tab Tarjeta ─────────────────→ TarjetaSheetView(.golpes)
 └─ tab Resultado ───────────────→ TarjetaSheetView(.resultado)
                                     └─ ResultsSheetView (embedded)
                                         ├─ selector (individual/pareja) → matchCard
                                         │    ├─ tap header/F9/B9 → MatchZoomView
                                         │    └─ tap chip "U" → UnitLogDetailView
                                         └─ scorecardStrip → holeDetailCard (inline)
                                              └─ tap jugador → dismiss + ContentView navega
                                                 a ese hoyo + dictado inline
```

---

## 4. Historial de este documento

- V2 (2026-04-04): inventario por archivo:línea. Obsoleto — líneas no coinciden con el código
  actual tras varios refactors.
- V3: nunca se llenó (archivo vacío).
- V4 (2026-10-02): este documento. Por nombre de struct, sin líneas. Mantenerlo actualizado cada
  vez que cambie una navegación.
