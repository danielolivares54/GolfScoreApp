# PROMPT — Caddie Score: Vista v2 (solo diseño, en paralelo a v1)

Read this whole file, then `DESIGN_SPEC.md`, then `CaddieStyleV2.swift`. Then work phase by phase.

## Goal

Build a **second, parallel set of screens ("Vista v2")** that improves how the app looks.
**v1 stays exactly as it is** and remains the default. The user switches between v1 and v2 with a toggle.
This is a visual change only: same data, same actions, same results, same money.

## Hard rules (do not break)

1. **New branch.** `git checkout -b diseno/v2-vistas` from the current branch. One commit per phase.
2. **No logic changes.** Do not modify `MatchManager.swift`, `Interpreter.swift`, `VoiceRecorder.swift`,
   `OpenAIService.swift`, `Persistence.swift`, `PlayerDirectory.swift`, `CatalogoEventos.swift`,
   `EventModels.swift`, `TextUtils.swift`, or any calculation in `BetCatalog.swift`.
   If v2 needs data that v1 already shows, call the same functions v1 calls.
   If something is truly missing, add a **read-only** computed property in a new file
   `Caddy_Score/V2/MatchManager+V2.swift`. Never change an existing function.
3. **Do not edit or delete v1 views.** The only edits allowed in existing files:
   - `Caddy_ScoreApp.swift` → `RootView`: show `ContentView()` or `ContentViewV2()` based on
     `@AppStorage("uiVersion") var uiVersion = "v1"`.
   - `ContentView.swift` → `topBar`: add **one** small button labelled `v2` that sets `uiVersion = "v2"`.
     Nothing else in that file.
4. **All new code in `V2/`** (the folder already created at the repo root). Every new type name ends in `V2` (e.g. `HoleScreenV2`).
   Use the shared components in `V2/CaddieStyleV2.swift`. Add new files to the app target.
5. **Same actions as v1.** Every v2 button calls the same action/sheet as its v1 equivalent
   (mapping in `DESIGN_SPEC.md` §3). Where v1 has no equivalent (e.g. voice "Deshacer"), do **not** invent logic — leave it out.
6. **No asset-catalog images** (the target has no Copy Bundle Resources phase). Icons = SF Symbols, drawings = SwiftUI shapes.
7. **Build after every phase.** Fix all errors. Run in the simulator with the same match in v1 and v2:
   scores, stroke dots, results and money must be identical.
8. **Data parity (all data per screen is viewed).** Every datum and every action a v1 screen shows must be
   visible on the matching v2 screen, or one tap away from it. Use the checklist of that screen in
   `GAP_ANALISIS.md` before closing a phase, tick it, and list anything left out. Nothing is dropped
   without Daniel's written OK (recorded in `PROGRESO.md`).
9. **Precedence.** Daniel's decisions in `PROGRESO.md` > `GAP_ANALISIS.md` > `DESIGN_SPEC.md` > the mockups.

## Current status and what's next

Done so far is in `PROGRESO.md` (P0 switch, Resultado, Tarjeta, Match detail in progress).
**From now on, work in the priority order of `GAP_ANALISIS.md` §1** (next: `HoleScreenV2` + Event/Note sheets + shared current hole).
The original phase table below is kept for reference.

## Phases (original plan)

| Phase | What | Done when |
|---|---|---|
| P0 | Branch, `V2/` folder, `CaddieStyleV2.swift`, `RootView` switch, `v2` button in v1, `Vista v1 / v2` switch in v2 | App builds; toggling switches screens both ways without losing data |
| P1 | `HoleScreenV2` (capture screen: par 4 and par 3 with oyes) + `RoundBarV2` | Scores, putts, oyes, voice dictation work as in v1 |
| P2 | `EventSheetV2` and `NoteSheetV2` | Units/events and notes are saved to the same place as in v1 |
| P3 | `TarjetaV2` | Same numbers as v1 Tarjeta (Golpes) |
| P4 | `ResultadoV2` | Same F9/B9/units/oyes/money as v1 Resultado; tapping a row opens v1 `MatchZoomView` |
| P5 | `HistorialV2` | Same rounds and amounts as v1 `RoundHistoryView` |
| P6 | `SetupV2` (steps 1–3 restyled; step 4 Apuestas embeds the existing v1 content) | Saving setup gives the same strokes/lanes/bets as v1 `GuidedSetupView` |

After each phase write 5 lines max in `docs/DISENO_V2/PROGRESO.md`: what changed, files, anything not done.

## Out of scope

New features, rule changes, bet logic, voice/LLM changes, Watch app, renaming v1 files, deleting dead code.
