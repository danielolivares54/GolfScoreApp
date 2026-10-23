# Caddy Score — Setup, stroke distribution and recalculation rules

Branch: `feature/apuestas-por-rival-y-zoom`. Status: **builds; not run in the app and not covered by tests.**

---

## 1. Rules (what the app must do)

### R1. Source of truth for the start hole
- The start hole used everywhere is `matchManager.startHole`.
- It changes when you tap **Siguiente** on the first Setup step (course + start hole, `GuidedSetupView.applyCampo`), when you press **Guardar** on the last step (`applySetup`), or when the app restores a saved match at launch.
- While you edit the first step, the value is only a draft on that screen. Nothing uses it until you tap Siguiente (or Guardar).
- Once you tapped Siguiente on step 1, Cancelar / Atrás / closing the sheet does **not** undo the course and start hole. Players, pairs and bets are still applied only on Guardar.
- A saved start hole must survive relaunching the app. The bundled `match_meta.json` must never overwrite it.

### R2. Order of play
- Order of play starts at the start hole and wraps around: start 10 gives 10, 11 … 18, 1, 2 … 9.
- The first nine played is **F9**. The second nine played is **B9**. This is not always holes 1–9 and 10–18.

### R3. Stroke distribution
- Each player's total strokes (and each pair's) is not changed by the start hole. Only which holes receive them changes.
- Whole rounds first: every full 18 strokes puts one stroke on every hole.
- The remainder is placed in an alternating sequence:
  - 1st, 3rd, 5th … stroke goes to the **first nine played**.
  - 2nd, 4th, 6th … stroke goes to the **second nine played**.
  - Inside each nine, the stroke goes to the hardest hole by SI **rank within that nine** (rank 1 = hardest).
- A half stroke goes to the next hole in that same sequence.
- An odd extra stroke therefore goes to the **first nine played**.
- Start hole 1 on a course with odd SIs on holes 1–9 and even SIs on holes 10–18 (CGM) gives the same result as the old SI-only rule. This was worked out by hand and is not covered by a test.

### R4. What a Setup save must recalculate
After pressing Guardar, these must reflect the saved setup, without reopening the screen:
- the stroke dots on the scorecard and hole table
- hole results, F9/B9 totals, pressures, oyes and money
- the pair lanes and who carries the strokes

### R5. What gets reset when Setup changes the F9
- Carry, Ajuste 50 and Doble Press are decided from the F9 result and store absolute holes.
- If a save changes any of these, they are switched off and must be re-enabled by the user: course, start hole, any player's strokes, the base pair, any pair's strokes or carrier.
- If nothing in that list changed, they are left alone.

### R6. What Setup never deletes
- Scores, putts, oyes, units, players and bet values are kept when the start hole changes.

### R7. Persistence
- One save of the full setup is written at the end of Setup, including a course-only change.
- `match_meta.json` is only used to seed a **new** match, when nothing was restored from the saved config.

### R13. Money and strokes when the F9 vuelta is 0 (tie: "F9 Zero", "salió Carry")
Applies to the individual matches and to the pair matches (`MatchManager.walletSnapshot`). It needs Vuelta, Presión and Match all switched on for that match; otherwise the normal calculation is used.
- Carry, Ajuste 50 and Doble B9 are not available (there is no F9 winner to ask them from): the F9 tie **is** the Carry.
- The F9 presión is paid as usual: F9 presiones × presión value.
- Vuelta B9, the B9 presiones and the Match are settled together with **one combined price**: vuelta value + presión value + match value of the template (pairs: the pair bet values). That price is paid once per unit won: the B9 vuelta counts 1 and every B9 presión counts 1 more. The Match is not paid separately.
- Anything else (units, etc.) is added as usual.
- Example: bets 100 / 100 / 100 (vuelta / presión / match) → combined price 300. B9 ends 5-3-1 (vuelta + 2 presiones = 3 units) → 3 × 300 = 900, plus the F9 presión and the rest. With 50 / 50 / 100 the combined price would be 200, so the same 3 units pay 600.
- **Results screen:** the F9 column says "Carry" (instead of E) once the 9 holes are played, and the match shows "F9 en cero · salió Carry · $300 por unidad" (`ResultadoRowV2.f9CarryPrice`).
- **Strokes for the next match:** with F9 Zero the strokes do **not** change, whoever wins B9. That is the bet rule of that player. When the match is closed the Directory records it as "F9 Zero (salió Carry) · los strokes no cambian" (`MatchManager.f9ZeroNote`) and keeps the strokes of the match as the strokes of the next one. With any other F9 result the strokes follow the usual rule (±1 for the match winner, or the Ajuste 50 formula).

### Change 1 — Stroke distribution follows the order of play
- **What changed:** `distributedStrokes` used only the course's fixed SI. It now uses the start hole too (R3). The logic is a static function so the live match and the history share it.
- **Impact for you:**
  - Changing the start hole moves the stroke dots to different holes.
  - Each player keeps the same total strokes.
  - Hole results and money change to match the new stroke holes.
- **Example (CGM, 3 strokes):** start 1 gives holes 4, 17, 2. Start 10 gives holes 17, 4, 11.
- **Not changed:** with 18 strokes every hole gets one, so nothing moves. Start hole 1 behaves as before on CGM.

### Changes 2–3 — Scorecard and hole table dots
- **What changed:** both had their own SI formula, so they could not follow the start hole or agree with the results. They now call the shared function.
- **Impact for you:** the dots always match the strokes used in the results.
- **Side effect:** the old code ignored half strokes in the hole table (it truncated them). It still shows whole strokes only.

### Change 4 — Round history
- **What changed:** the history had a private copy of the formula. It now uses the shared one with the start hole saved in each round.
- **Impact for you:** rounds that started on hole 1 show the same stroke stats as before. Rounds that started elsewhere may show different "receive/give" stats, because they now follow the new rule.

### Changes 5–6 — Reset of Carry / Ajuste 50 / Doble Press
- **What changed:** before, only a start-hole change cleared them. Now the reset runs whenever a save changes the course, start hole, player strokes, base pair, pair strokes or carrier (R5).
- **Impact for you:** if you change strokes or pairs in Setup, an active Carry turns off. You turn it back on if it still applies. Saving Setup without changes does nothing to it.

### Change 7 — Single save and refresh
- **What changed:** each setter saved on its own, and a course-only change (`setCourse`) never saved. Setup now ends with one full save and a refresh.
- **Impact for you:** a course change is stored and does not revert after closing the app, and all screens redraw with the saved setup.

### Change 8 — Pair bet switches kept
- **What changed:** saving Setup rebuilds the pair lanes with new IDs, and the per-pair bet switches were keyed by ID, so they went back to defaults. They are now carried over by the pair's opponents.
- **Impact for you:** the pair bet toggles stay as you set them after saving Setup.

### Change 9 — Bet instances rebuild
- **What changed:** for 2-player base teams the rebuild returned early and skipped `rebuildBetInstances()`.
- **Impact for you:** none visible today, since nothing else reads `betInstances`. It removes a stale copy.

### Change 10 — Saved config before `match_meta.json`
- **What changed:** `setupOnAppear` applied `match_meta.json` (start hole 1, fixed roster) every time, before restoring the saved config. That overwrote your saved start hole. And because the roster was already filled, the saved roster and start hole were not restored.
  - Now: the saved config is restored first.
  - Then `match_meta.json` seeds players and start hole only if nothing was restored, followed by a second restore pass for strokes and pairs.
- **Impact for you:**
  - The start hole, roster and course you saved stay after relaunch.
  - **One-time action:** the saved file may already hold hole 1 from earlier overwrites. Set the start hole again in Setup and press Guardar.

### Change 11 — Course and start hole apply on Siguiente
- **What changed:** before, the course and start hole were only applied when you reached the last step and pressed Guardar. Now `applyCampo()` runs when you tap Siguiente on step 1. It sets the course and start hole, resets Carry / Ajuste 50 / Doble Press only if the course or start hole actually changed, saves, and refreshes the screens.
- **Why only this step:** it doesn't depend on players or pairs. Applying players, pairs and bets per step would break Cancelar, apply half-finished setups and reset bets too often, so those stay on Guardar.
- **Impact for you:**
  - The dots, results and money already follow the new start hole after Siguiente.
  - A line under the start-hole picker warns that Siguiente applies it, redistributes strokes and switches off Carry / Ajuste 50 / Doble Press.
  - **Cancelar after Siguiente keeps the new course and start hole.** To go back, set them again on step 1 and tap Siguiente.

### Change 12 — Note field no longer suggests 3 putt / hole out
- **What changed:** the note field on the hole card said "penalidad, 3 putt, chupes…". It now says "penalidad o comentario…" (`ContentView.swift`).
- **Impact for you:** 3 Putt and Hole Out are chosen with the Unidades buttons, not typed as notes. Nothing was removed from the units catalog.

### Change 13 — Putts are an optional bet (R8)
- **Rule R8:** the user's own putts are always recorded. Other players' putts are asked for, audited and shown only while the putts bet is active (`puttsBetUnits > 0`). The bet's scope is F9, B9 or 18 holes (the existing "Por vuelta" stays for saved data).
- **What changed:**
  - `MatchManager`: `puttsBetActive`, `tracksPutts(alias:)`, and two new scopes `PuttsBetMode.f9` / `.b9`.
  - `GuidedCaptureView`: it used to ask every player for putts always. Now it asks the user always and the others only with the bet on.
  - `HoleAuditView` and the audit button in `ContentView`: "missing putts" warnings only count the tracked players. The inline putts stepper follows the same rule.
  - Scope pickers in `MoneyTrackerView` and the template editor (`BetCatalog.swift`) now offer F9, B9, 18 holes and Por vuelta.
- **Impact for you:**
  - With the putts bet off, you are asked only for your own putts, and other players' missing putts no longer turn the audit orange.
  - With it on, everyone's putts are asked for and audited as before.
- **Not done yet:** the putts bet money. `puttsBetMode` and `puttsBetUnits` are not read by the money calculation, so choosing F9 / B9 / 18 does not change any amount yet. The settlement rule is still to be defined.
- **Note:** `puttsBetUnits` starts at 2 in code, so the bet counts as active until a template or the money screen sets it to 0.

### Change 14 — Mi Historial: strokes, putts, two columns, split score rows (R9)
- **Rule R9:** statistics are about the user (first player of each closed round). Every figure has two columns: **Acumulado** (all closed rounds) and **Este match** (the most recently closed round).
- **What changed** (`RoundHistoryView.swift`, `MyHistoryView`):
  - Score table now has **Águila o mejor, Birdie, Par, Bogey, Doble bogey (+2), Triple bogey (+3), +4 o más**. "Doble o peor" no longer exists.
  - New card **Golpes (medal, bruto)** and **Putts**: F9, B9 and Total 18. Acumulado is the **average per round**; Este match is that round's actual figure.
  - F9 / B9 follow each round's own start hole. A nine with any hole missing (score, or putts for the putts rows) is left out, so partial rounds don't pull the averages down.
- **Impact for you:** open Mi Historial after closing a round: the right column is that round. Old closed rounds already carry scores, putts and start hole, so they appear in the statistics. Rounds closed before putts were recorded show "—" for putts.
- **Not included:** net (with strokes) totals.

### Change 15 — Putts bet is a catalog tag (R10)
- **Rule R10:** the putts bet is defined by the **PUTTS** tag in the units catalog. Tag **on** = bet open, **Vale** = price in units, **Alcance** = F9 / B9 / 18 / Vuelta. Tag **off** (default) = bet closed: only the user's putts are recorded, as statistics (R8).
- **What changed:**
  - `BetDefinition.puttsScope` (optional, old catalogs still load); `BetDefinitionStore` adds the PUTTS tag, off, to new and existing catalogs; the Catálogo row shows an Alcance picker for it.
  - `MatchManager.syncPuttsBetFromCatalog()` copies the tag into the match when the match is built and when the Apuestas screen closes. `puttsBetUnits` now starts at 0 (closed).
  - The money-screen scope buttons write the scope to the tag but do **not** open the bet. Templates no longer set putts, and the Putts section was removed from the template editor (saved template values are kept untouched).
- **Impact for you:** the putts bet is **closed on first launch after this update**, even if a template had it on. Turn it on in Apuestas → Catálogo → Putts. A Setup save no longer overwrites it with a template's values.
- **Not done:** the putts **money**. The tag now carries on/off, price and scope, but no amount is calculated from it yet — the settlement rule still has to be confirmed.

### Change 16 — Setup keeps the strokes of players already in the match (R11)
- **Rule R11:** a player already in the match keeps exactly the strokes the match has (including 0) when Setup opens and saves. Only what you edit in Setup changes them. New players added in Setup still get the directory's strokes when you add them by name.
- **What changed** (`GuidedSetupView.syncStrokes`): before, an existing player at 0 strokes was filled from the saved directory, so saving Setup mid-match (for example to adjust one rival) also changed other players' strokes and their money. Found in the simulator demo (Fernando, Ricardo and Anselmo changed when only Roberto was edited).
- **Impact for you:** a mid-match stroke update in Setup changes only the player you edited. The results and money recalculate as before.
- **Decided (R12):** a stroke change (one more, one less, or a new total) applies to **all 18 holes**, including holes already played. The whole round is recalculated from the start hole, in order of play, and the strokes are reassigned to holes by the R3 rule. There is no "from the current hole forward" mode.

---

## 3. Worked example — 3 strokes on CGM, start 10 changed to 1

| Order | Stroke | Goes to | Hole |
|---|---|---|---|
| Start 10 | 1st | hardest of holes 10–18 | 17 |
| Start 10 | 2nd | hardest of holes 1–9 | 4 |
| Start 10 | 3rd | 2nd hardest of holes 10–18 | 11 |
| Start 1 | 1st | hardest of holes 1–9 | 4 |
| Start 1 | 2nd | hardest of holes 10–18 | 17 |
| Start 1 | 3rd | 2nd hardest of holes 1–9 | 2 |

After the change, hole 11 loses its stroke and hole 2 gains one. Holes 4 and 17 keep theirs. The total stays 3.

---

## 4. Test checklist (to do in the app)

1. Start a round on hole 1 with one opponent who receives 3 strokes. Dots should be on holes 4, 17, 2.
2. Open Setup, set the start hole to 10 and tap **Siguiente**. Dots should already move to 17, 4, 11 and the total should stay 3. Then close the sheet with Cancelar: the start hole should stay 10.
3. Close and reopen the app. The start hole should still be 10 and the dots unchanged.
4. Turn on a Carry, open Setup and save with no changes. The Carry should stay on.
5. Change a player's strokes and save. The Carry should switch off.
6. Set a pair bet switch, then save Setup. The switch should keep its value.
7. Check the money screen after each save. It should match the hole results.
8. Open a closed round that started on hole 1. Its stroke stats should look the same as before.

---

## 5. Known limits and open points

- **Not run.** The build succeeds, but I could not run the code-snippet checks. Nothing here is covered by an automated test.
- **Odd extra stroke** goes to the first nine played. If you prefer the second nine, it is a one-line change in the sequence formula in `MatchManager.distributedStrokes`.
- **Fresh-match default:** `MatchManager.startHole` starts at 10 in code (`MatchManager.swift:285`) until a setup or saved config sets it. Not changed.
- **Pair bet switches** are not part of the saved config, so they still reset when the app relaunches.
- **Dead code:** `SetupWizardView` and `CoursePickerView` (`StartHolePickerView`) are never shown. They call `updateStartHole` with scores reset and no save. Not touched.
- **History:** closed rounds are recomputed with the new rule, so stats for rounds that started away from hole 1 may differ from what was shown before.
