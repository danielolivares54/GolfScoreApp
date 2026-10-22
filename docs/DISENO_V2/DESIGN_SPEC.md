# DESIGN_SPEC — Caddie Score Vista v2

Visual spec for the v2 screens. Logic and data come from the existing `MatchManager`; this file only says how things look and which existing action each control calls.
Reference mockups: the "Sistema v2" page of the design canvas (Daniel can export PNGs into `docs/DISENO_V2/screens/`).

---

## 1. Rules

1. **One datum, one look.** Hole, par, HCP, score, strokes, events, oyes and result are drawn with the same component on every screen (`CaddieStyleV2.swift`).
2. **Relaxed type.** SF Pro (system) everywhere, digits with `.monospacedDigit()`. No monospaced design, no serif.
3. **No "vs".** An individual match is named by the rival code (`ALC`). A pair is named by Daniel's partner (`con MIG`) with the rivals underneath (`ALC · FED`).
4. **Strokes in words.** "ALC recibe 3½", "DAN recibe 5". Never "+3 / −3". Half strokes always shown as `½`.
5. **Voice first.** A large mic button in the centre of the bottom bar on every round screen. Tapping a player's name dictates only that player (same as v1 avatar tap). After dictation, show what was understood.
6. **Events and notes from the bottom bar**, never as fixed buttons inside each player row.
7. **Up to 3 pairs** (lanes) everywhere results are shown.
8. **One button style.** Steppers 48×48 pt, one green primary button per screen, text buttons without underline, no double rings.
9. **Data parity.** Every datum and action of the v1 screen is visible in v2 or one tap away. The per-screen checklist is in `GAP_ANALISIS.md`. Daniel's decisions in `PROGRESO.md` override this spec (e.g. no outlines on score marks, pair names joined with "–", oyes counted inside Unid).
10. **Follow the real model.** Pairs = base pair + lanes (`LaneModel`: base, opp, strokes, strokeCarrier). Don't add controls the model doesn't have (e.g. a per-pair on/off switch shown in the mockup).

## 2. Tokens (already in `CaddieStyleV2.swift`)

| Token | Hex | Use |
|---|---|---|
| `ink` | #1A1A17 | numbers, names |
| `secondary` | #5E584C | labels, par, HCP (never lighter) |
| `background` | #F7F3EA | screen background |
| `surface` | #FFFFFF | cards |
| `line` | #E4DCCB | card borders |
| `green` | #157A3B | primary action, under par, winning |
| `red` | #B3261E | over par, losing |
| `stroke` | #1F4E9C | **only** strokes |
| `unitBg` / `unitFg` | #F3E2B3 / #6E4600 | **only** events/units and oyes |

Spacing 8/16/24. Radius 10 (cells) / 16 (cards). Minimum tap target 48 pt. Text minimum 13 pt.

Score marks (golf standard): circle = birdie, double circle = eagle or better, square = bogey, double square = double bogey or worse, plain = par, dashed box = not entered.

F9 / B9 follow the app rule R2: **F9 = first nine played** (with start 10: holes 10–18). Label segments with the real hole range, e.g. `F9 · 10–18`.

---

## 3. Screens

### 3.1 `ContentViewV2` / `HoleScreenV2` — capture (replaces the look of v1 `ContentView`)

Top to bottom:

1. **Top bar** (56 pt): `CGM · Sale H10` on the left. Icons right, 44 pt each, same actions as v1 `topBar`: audit semáforo → `showAudit`; history → `showRoundHistory`; gear → `showGuidedSetup` (v2: `SetupV2`); flag → `showCerrarRondaConfirm`. Remove the duplicate "Sale en H10" pill and the H-badge.
2. **Hole card** (green, 84 pt, radius 16): ‹ prev · `HOYO · 2 DE 18` (small) · hole number (42 pt heavy) · `ParTagV2` + `HcpTagV2` (white variants) · next ›. Prev/next = same navigation as v1.
3. **Match strip** (4 equal chips, 46 pt): one chip per individual rival (`ALC`, `MIG`, `FED`) with live status (`MatchStatusV2`), plus one `Parejas` chip showing the status of each active lane side by side. Data = what v1 `ResultsSheetView` shows.
4. **Voice banner** (only after a dictation): mic icon, the understood text in quotes, a line "Aplicado · falta FED" (players still without a score). While listening: "Escuchando…" with level bars. No undo (v1 has none) — the player taps the name to re-dictate.
5. **Player rows** (one card, rows 68–76 pt, all the same height):
   - Left: player code (18 pt bold) + small mic glyph (tap = dictate this player, same as v1 avatar tap) + stroke dot if the player receives a stroke on this hole.
   - Under the name: strokes line in `stroke` blue — for DAN "recibe de FED" / "da a ALC", for a rival "recibe 1 de DAN" (from `distributedStrokes`); otherwise "sin stroke aquí" in secondary.
   - Right: `StepButtonV2(−)` · `ScoreMarkV2` · `StepButtonV2(+)`. Same setter as v1 `editablePlayerGrid`.
   - Putts: keep the v1 putts control (R8: own putts always; others only if putts bet is on), placed as a small stepper under the score when applicable.
   - **Remove** the per-row "Unidad: 3 Putt / Hole Out" buttons and the "penalidad, 3 putt, chupes…" row.
6. **Par 3 only — Oyes card:** title `OYES · orden de cercanía`, four chips (`OyeChipV2`). Tap players in order of proximity; chip shows `1º`, `2º`…; tap again to remove. Reads/writes `oyesRanksByHole` exactly as v1 does. Under it: event pills of this hole and the note preview (✎ text).
7. **Bottom bar** `RoundBarV2` (84 pt, 5 slots): Tarjeta · ＋ Evento (gold) · **Mic** (62 pt green circle, centre; while recording shows a stop square + halo) · Nota · Resultado.

### 3.2 `EventSheetV2` — bottom sheet

Title `Evento · Hoyo 14` + small mic (dictate the event). Step 1: player picker (4 chips 52 pt, selected = ink fill). Step 2: grid of events from the existing catalog (`CatalogoEventos` / `catalogo_eventos_caddie.json`), each tile shows label + code + value (`3 Putt · 3P −1`). Calculated events (birdie/eagle) shown greyed as "automático". Saving = same call v1 uses to add a `UnitEvent` to `unitEventsByHole`. Event pills on the hole screen: tap → confirm remove (same as v1 removal if it exists; otherwise no remove).

### 3.3 `NoteSheetV2`

Single text field "Comentario del hoyo…" + mic for dictation. Binds to the same storage as v1's "penalidad o comentario…" field.

### 3.4 `TarjetaV2` (replaces look of `TarjetaSheetView` golpes mode)

Top: back `‹ Hoyo 14` · segmented `F9 · 10–18 | B9 · 1–9`. Legend line (birdie, bogey, stroke, evento/oye). Table: Hoyo | P | HCP (outlined) | one column per player. Cells = `ScoreMarkV2(size: 32)` with stroke dot top-right and gold square bottom-left if the player has an event/oye on that hole. Current hole row tinted green. Footer row (ink background): nine label, par sum, gross totals. Rows 52 pt; nine holes fit without scrolling. Bottom bar with Tarjeta active.

### 3.5 `ResultadoV2` (replaces look of `ResultsSheetView`)

- Top: back `‹ Hoyo 14` · "después de N hoyos".
- **Total card**: "Daniel · total en curso", subtitle "3 individuales · 2 parejas activas", amount large (`MoneyTextV2`, 32 pt, regular weight).
- **Individual card**: header row `Individual · F9 · B9 · Unid · Oyes · $`. One row per rival: code (16 pt bold) + strokes line (`ALC recibe 3`) · statuses · money.
- **Parejas card**: same columns, up to 3 rows: `con MIG` + `ALC · FED · FED recibe 2½`. Inactive lane row at 50 % opacity "no se juega hoy".
- Tap a row → existing `MatchZoomView` (hole by hole + presses). Tap Unid → existing `UnitLogDetailView`.
- Remove the separate "Últimos 3 hoyos" block; the screen is used by the two cards.
- Font for this screen: regular/semibold weights, no heavy monospaced numbers.

### 3.6 `HistorialV2` (replaces look of `RoundHistoryView`)

Top: title `Historial` · `Todos ▾` filter (same as v1) · stats icon (→ `MyHistoryView`) · close. One card per round: `20 oct · CGM` / `Sale H10`, total right (green/red; `$0` grey; open round shows tag `En curso`). One row per rival: name + money; line 2 `F9 2↑ · B9 1↓ · match ganado`; line 3 in blue `DAN recibe 8 → próximo: recibe 7`. Remove the `VIGENTE` badges and the beige "Strokes esa ronda" box.

### 3.7 `SetupV2` (replaces look of `GuidedSetupView`)

Header: `Cancelar`/`Atrás` text button · `Nueva ronda` · green `Siguiente` / `Empezar`. 3-segment progress bar + `PASO n DE 3 · …`. Keep the existing R1/R5 behaviour (`applyCampo` on Siguiente of step 1, `applySetup` on save).

1. **Campo:** course row (`CGM · 18 hoyos · Cambiar`), two quick chips `Sale H1` / `Sale H10`, stepper for any other start hole, note "La tarjeta se llena en orden de juego: 10 → 18, luego 1 → 9." Keep the v1 warning text that Siguiente applies the start hole.
2. **Jugadores y strokes:** player list (40 pt avatar, name, `Tú`/`Rival`, trash icon 44 pt, no double ring), `＋ Agregar jugador · 4 de 5`. Per rival: name + bet template chip (`TPCH ▾`); row `− 3½ + [½] [ALC | DAN]` (who receives); blue line `ALC recibe 3½ · hoyos 17, 4, 11 y ½ en 2` computed with `distributedStrokes` and the start hole.
3. **Parejas:** up to 3 cards (`Pareja 1 · con MIG`, `Rivales: ALC · FED`, on/off switch). Stroke stepper with `½`, `¿Quién recibe?` with 4 player chips, blue line `FED recibe 2½`. Below: bet template chips (`S y D`, `S y D 4`, `Jueves`, `TPCH`, `Fdez`) and the amount/unit fields — same bindings as v1.
4. **Apuestas:** embed the existing v1 step content unchanged inside the v2 frame.

---

## 4. Acceptance checklist (run with the same match in v1 and v2)

1. Toggle v1 ↔ v2 at any moment without losing scores, oyes, events or notes.
2. Stroke dots on Hole screen and Tarjeta are on the same holes as v1 (CGM, start 10, 3 strokes → 17, 4, 11).
3. ½ strokes display as `½` and give the same results as v1.
4. F9/B9 statuses, units, oyes and money in `ResultadoV2` equal v1 for every individual match and every lane.
5. Voice dictation (whole hole and per player) writes the same values as v1.
6. Par 3 holes show the Oyes card; other holes don't.
7. All tap targets ≥ 44 pt; no text lighter than `secondary`; no "vs" anywhere in v2.
