# GAP_ANALISIS — v1 → Vista v2 (data parity by screen)

Date: 2026-10-21. Built from the v1 code (`MAPA_PANTALLAS_V4.md`, the views' visible texts) and the current `V2/` folder + `PROGRESO.md`.

**Rule (data parity):** every datum and every action that a v1 screen shows must be visible in the matching v2 screen, or **one tap away** from it (and the row below says where). Nothing is dropped silently. If a datum is deliberately left out, it must be written here with Daniel's OK.

Status: ✅ done · 🟡 partial · ⬜ not started · ➖ out of v2 scope (stays v1)

---

## 1. Summary — the right screens, in priority order

| # | v1 screen (struct) | v2 screen | Status | Priority |
|---|---|---|---|---|
| 1 | `ContentView` (hole capture) | `HoleScreenV2` inside `ContentViewV2` | 🟡 manual capture done; events/notes (Paso 4) and voice (v2t) pending | P-A |
| 2 | `ResultsSheetView` (+ `TarjetaSheetView` resultado) | `ResultadoV2` | 🟡 | P-B |
| 3 | `MatchZoomView` + match card | `MatchDetailV2` | 🟡 in progress | P-B |
| 4 | `TarjetaSheetView` (golpes) | `TarjetaV2` | 🟡 | P-B |
| 5 | (new presentation) units / notes | `EventSheetV2`, `NoteSheetV2` | ⬜ | P-A (with #1) |
| 6 | `HoleAuditView` + `HoleCorrectionSheet` | `AuditV2` | ⬜ | P-C |
| 7 | `GuidedSetupView` (4 steps) | `SetupV2` | 🟡 steps 1–3 done; Apuestas/Directorio/Log open the v1 views | P-C |
| 8 | `RoundHistoryView` | `HistorialV2` | ⬜ | P-D |
| 9 | `MyHistoryView` (stats) | `MyHistoryV2` | ⬜ | P-D |
| 10 | `UnitLogDetailView` | v1 view shown from v2 (restyle later) | ✅ opened from ResultadoV2 (Unid) and MatchDetailV2 | P-D |
| 11 | `CarryB9CardView` | v1 view shown from v2 (restyle later) | ✅ opened from MatchDetailV2 | P-D |
| 12 | `BetSetupSheet`, `BetsHubView`, bet/template editors | v1 views shown from v2 (SetupV2 → Apuestas) | ✅ | P-E |
| 13 | `PlayerDirectoryView` (+ edit) | v1 view shown from SetupV2 | ✅ | P-E |
| 15 | Catalog editor ("tag" de apuestas: activar/desactivar unidades, valores, nuevas) | `CatalogoV2` (Paso 11) | ✅ | done |
| 14 | Close round (`confirmationDialog`) | same dialog from v2 top bar | ⬜ | P-A |
| — | `GuidedCaptureView` (Siri only), `RescueCaptureView`/`FuzzyReviewView`, `SplashView` | — | ➖ keep v1 | — |
| — | Dead code: `ScorecardView`, `CardView`, `MoneyTrackerView` (body), `SetupWizardView`, `MatchSummaryView`, `CoursePickerView`, `StartHolePickerView`, `IntentTestView` | — | ➖ not ported | — |

---

## 2. Screen-by-screen gaps

### 1. `ContentView` → `HoleScreenV2` ⬜
v1 shows / does — all must exist in v2:

- [x] Course id, "Sale en H{n}"
- [x] Audit semáforo (🟢/🟠/🔴 = completeness) → `HoleAuditView`
- [x] ⚙ → Setup · 🕘 → `RoundHistoryView` · 🏁 → close-round dialog · `v1/v2` switch
- [x] Hole number, par, HCP; prev / next hole; "Hoyo N listo →"
- [x] Per player: code, score (gross), dictation state/transcript ("sin anotar" / text), tap name = dictate this player
- [x] Putts stepper (own always; others only when putts bet is on — R8)
- [x] Par 3: oye rank per player (v1 "Oye 1–4")
- [x] Manual units (3 Putt, Hole Out, catalog) per player → moves to `EventSheetV2`, pills visible on the hole
- [x] Hole note ("penalidad o comentario…") → `NoteSheetV2`, preview visible on the hole
- [x] Stroke info for this hole (who receives) — v1 shows it only on Tarjeta/Resultado; v2 adds it here
- [x] Live match status per rival and per lane — v2 addition (data from `resultadoRowsV2()`)
- [ ] Bottom: Tarjeta · Evento · Mic · Nota · Resultado
- [x] "demo" button (destructive) → **not** in v2 (Daniel OK, 21-oct)
- [ ] Voice complete (see §3 decision 4): whole-hole mic, per-player dictation, understood/applied banner, review step, Deshacer
- Gap to solve first: **current hole is `@State` per view** (PROGRESO P0). Share it so v1↔v2 and "‹ Hoyo N" land on the same hole.

### 2. `ResultsSheetView` → `ResultadoV2` 🟡
- [x] Total general; one row per individual match and per lane; F9/B9 status; Unid (oyes inside); $; presiones; Carry
- [x] Tap Unid → `UnitLogDetailView`
- [x] "‹ Hoyo N" back
- [ ] Money breakdown per match (V vuelta / P presión / C carry / M match / U unidad) — v1 match card shows it; confirm it is in `MatchDetailV2` (one tap away)
- [ ] v1 `scorecardStrip` + `holeDetailCard` (hole detail, tap player = correct by voice): removed from Resultado by Daniel's decision → must be reachable in `MatchDetailV2` (hole by hole) and `TarjetaV2` (tap cell)

### 3. `MatchZoomView` / match card → `MatchDetailV2` 🟡
- [ ] Per hole: H, par, HCP, gross of each side, unit marks, Res, Acum, subtotal per nine
- [ ] Concepts table F9, B9 (×2), Match, Carry, Ajuste 50, Unidades, Total, who pays whom
- [ ] Buttons Carry / Ajuste 50 / Doble B9, carry requester in pairs, B9 refresh state
- [ ] Links: hole by hole, Carry card, unit log
- [ ] Strokes in words for this match ("ALC recibe 3½"), net strokes per hole ("→")

### 4. `TarjetaSheetView` golpes → `TarjetaV2` 🟡
- [x] Hole, par, HCP, gross per player, stroke dots, unit/oye dot, nine totals, Total 18
- [x] **Putts** — v1 shows putts "(n)" and putt totals; `TarjetaV2` has none → add a **"Putts" toggle** (Daniel, 21-oct)
- [x] Current hole row highlight (needs shared current hole)
- [x] Tap a cell → opens the correction sheet (score, putts, oye, units); tap the hole number → go to that hole (voice later with v2t) (v1 does this from `holeDetailCard`)

### 5. `EventSheetV2` / `NoteSheetV2` ⬜
- [ ] Same catalog as v1 (`betCatalog` manual individual units, not OYES — see `MatchDetailV2.manualUnitBets`)
- [ ] Add/remove writes the same `unitEventsByHole` / note storage as v1
- [ ] Voice entry for an event (optional — only if v1 interpreter already supports it)

### 6. `HoleAuditView` → `AuditV2` ⬜
- [x] List of holes with data, incomplete count, per-hole status, oye rank, units, net "→"
- [x] Tap → correction sheet (score, putts, oye) → "Guardar corrección" (same save)

### 7. `GuidedSetupView` → `SetupV2` 🟡
- [x] Step 1: course, start hole (and the R1 warning text)
- [x] Step 2: players (directory link, add/remove, "4 de 5"), strokes per rival with ½, **sign hint in words** (v1: "Positivo = le das strokes · negativo = te da strokes" → v2: "ALC recibe 3½"), bet template per rival
- [x] Step 3: **base pair** (`PAREJA BASE`), lanes vs each opponent pair (rotating), strokes per lane with ½, carrier ("Da strokes"/lleva), bet template, amount, unit value, log
- [x] Step 4: Apuestas (catalog) — embed v1 content
- Note: v1 has no pair on/off switch and builds lanes from the base pair. The v2 mockup's "3 independent pairs with a switch" must follow the real model (base pair + lanes); don't add a switch.

### 8. `RoundHistoryView` → `HistorialV2` ⬜
- [x] Per round: date, course, start hole, total $
- [x] Per rival: name, vuelta and match points, F9/B9, $, strokes that round, next-match strokes, "vigente" state (show as text only if it means something; else drop with OK)

### 9. `MyHistoryView` → `MyHistoryV2` ⬜
- [x] Golpes (medal, bruto) F9/B9/18 — Acumulado vs Este match
- [x] Putts F9/B9/18
- [x] Score distribution (águila … +4)
- [x] Impacto del stroke (% win/tie when giving / receiving)
- [x] Promedio vs par por tipo de hoyo

### 10–13. Secondary screens
- `UnitLogDetailView`, `CarryB9CardView`, `BetSetupSheet`/`BetsHubView`/editors, `PlayerDirectoryView`: open the **v1 views** from v2 first (data parity guaranteed); restyle only after P-A…P-D are done.

---

## 3. Decisions for Daniel

1. ✅ "demo" button: **hidden in v2** (stays only in v1).
2. ✅ Putts in `TarjetaV2`: **a "Putts" toggle** (off = scores, on = putts in the same cells + putt totals per nine).
3. ✅ History "VIGENTE" badge: dropped (Daniel, 21-oct); replaced by the blue line "DAN recibe 8 → próximo: recibe 7".
4. ✅ **Voice is the core of the app and must be complete in v2.** Reuse the existing v2t pipeline (`VoiceRecorder` → `Interpreter`/`OpenAIService` → same validation and setters as v1) — no new parsing or rules. In v2:
   - Big mic in the centre of `RoundBarV2` dictates the whole hole; tapping a player's name dictates only that player (same as v1).
   - Show what was understood and what was applied ("Aplicado · falta FED"), and the same review/confirmation step v1 uses when the interpreter is unsure.
   - **Deshacer** the last dictation: implemented in the v2 layer only — before applying, keep a snapshot of that hole's values (scores, putts, oyes, units) and, on Deshacer, write them back with the same setters v1 uses. No change to `MatchManager`.
   - Mic also available in `EventSheetV2` and `NoteSheetV2` if the v1 interpreter already handles events/notes; otherwise the note is dictated as plain text.
