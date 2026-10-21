# PLAN_PASOS — Vista v2: pasos, archivos y criterio de terminado

Documento único para el agente de Xcode. Un paso a la vez; al terminar cada paso: compilar, probar, anotar y **detenerse para revisión de Daniel**.

---

## Prompt para pegar en el agente

> Lee `docs/DISENO_V2/PLAN_PASOS.md` completo y trabaja SOLO el siguiente paso pendiente.
> Reglas: `docs/DISENO_V2/PROMPT.md` (sobre todo regla 2 sin cambios de lógica, regla 3 no tocar v1, regla 8 paridad de datos).
> Antes de empezar lee los archivos de "Leer" del paso. Crea/edita solo los archivos de "Crear/Editar".
> Al terminar: compila, corre las pruebas, prueba en simulador la misma ronda en v1 y v2, marca el checklist de esa pantalla en `GAP_ANALISIS.md`, escribe máximo 5 líneas en `PROGRESO.md`, haz commit en `diseno/v2-vistas` y detente.

---

## Documentos de referencia (siempre)

| Archivo | Uso |
|---|---|
| `docs/DISENO_V2/PROMPT.md` | Reglas que no se rompen |
| `docs/DISENO_V2/GAP_ANALISIS.md` | Checklist de datos por pantalla (paridad) |
| `docs/DISENO_V2/DESIGN_SPEC.md` | Cómo se ve cada pantalla |
| `docs/DISENO_V2/PROGRESO.md` | Bitácora + decisiones de Daniel (mandan sobre todo) |
| `V2/CaddieStyleV2.swift` | Componentes compartidos v2 |
| `REGLAS_SETUP_Y_GOLPES.md` | Reglas R1–R12 (orden de juego, strokes, ½, F9/B9) — no se cambian |
| `MAPA_PANTALLAS_V4.md` | Mapa de pantallas v1 y su navegación |

Estado al 21-oct: hechos P0 (switch v1/v2), ResultadoV2, MatchDetailV2, TarjetaV2 (sin putts), Paso 1 (hoyo compartido). Paso 3 (voz) retirado: irá como v2t iPhone + Watch. **Siguiente: Paso 2.**

---

## Paso 1 — Hoyo actual compartido

- **Objetivo:** v1 y v2 abren en el mismo hoyo; "‹ Hoyo N" y la fila verde de Tarjeta funcionan.
- **Leer:** `Caddy_Score/ContentView.swift` (`currentHoleIndex`, navegación de hoyos), `V2/ContentViewV2.swift`.
- **Crear/Editar:** `V2/ContentViewV2.swift`. **Excepción permitida en v1:** cambiar solo la declaración de `currentHoleIndex` en `ContentView.swift` de `@State` a `@AppStorage("currentHoleIndex")` (o equivalente mínimo). Nada más en v1.
- **Terminado cuando:** cambiar v1↔v2 en el hoyo 14 deja ambas vistas en el hoyo 14; reiniciar la app conserva el hoyo.

## Paso 2 — `HoleScreenV2` (captura manual)

- **Objetivo:** pantalla principal de v2 con todos los datos de captura de v1 (GAP §2.1).
- **Leer:** `ContentView.swift` → `topBar`, `editablePlayerGrid`, `legend`, `bottomBar`, botón "Hoyo N listo →", oyes en par 3 (`setOyesRanks`), stepper de putts (regla R8 en `REGLAS_SETUP_Y_GOLPES.md`); `MatchManager.swift` → `players`, `holes`, `playOrder()`, `distributedStrokes`, `applyHoleEntry`, `setOyesRanks`; `V2/MatchManager+V2.swift` (`resultadoRowsV2()` para la tira de estado).
- **Crear/Editar:** `V2/HoleScreenV2.swift` (nuevo), `V2/ContentViewV2.swift` (usar HoleScreenV2 como inicio), `V2/MatchManager+V2.swift` (solo lectura si falta algo).
- **Incluye:** barra superior (semáforo de audit, historial, ⚙, 🏁 con el mismo diálogo de cierre, Vista v1), tarjeta verde del hoyo, tira de estado por rival y parejas, filas por jugador (−/score/+, putts según R8, línea de strokes en palabras), tarjeta de Oyes solo en par 3, `RoundBarV2`, y ganchos vacíos para voz (mic central y toque en nombre; se conectan con v2t). Sin botón "demo".
- **Terminado cuando:** capturar a mano una ronda completa en v2 da exactamente los mismos scores, putts, oyes, resultados y dinero que en v1.

## Paso 3 — RETIRADO de v2 (decisión de Daniel, 21-oct)

La voz NO se construye dentro de la Vista v2. Se hará después como **v2t**, un módulo compartido por iPhone y Apple Watch (contrato: `docs/WATCH_VOZ_CONTRATO.md`, `SSOT_DIALOGO_V2T.md`), para tener un solo pipeline de dictado, banner y Deshacer en ambos dispositivos. Mientras tanto la voz sigue funcionando en v1 sin cambios.
- Consecuencia en v2: `HoleScreenV2` captura a mano; deja el espacio del mic central y el toque en el nombre del jugador como **ganchos vacíos** (sin lógica) para conectar v2t después.
- Se conserva la numeración de los pasos para no romper referencias en otros documentos.

## Paso 4 — `EventSheetV2` y `NoteSheetV2`

- **Leer:** `V2/MatchDetailV2.swift` (`manualUnitBets`), `MatchManager.swift` (`addUnitEvent`, `removeUnitEvent`, `unitEventsByHole`), `ContentView.swift` (botones Unidad 3 Putt / Hole Out y el campo "penalidad o comentario…" con su binding).
- **Crear/Editar:** `V2/EventSheetV2.swift`, `V2/NoteSheetV2.swift` (nuevos), `V2/HoleScreenV2.swift` (abrir hojas desde `RoundBarV2`, píldoras de eventos y vista previa de nota en el hoyo).
- **Terminado cuando:** eventos y notas agregados/quitados en v2 aparecen igual en v1 (y al revés).

## Paso 5 — `TarjetaV2`: Putts, hoyo actual, tocar celda

- **Leer:** `ContentView.swift` → `TarjetaSheetView` (putts "(n)" y totales), `holeDetailCard` (tocar jugador → corrección por voz).
- **Crear/Editar:** `V2/TarjetaV2.swift`, `V2/MatchManager+V2.swift`.
- **Incluye:** toggle **"Putts"** (apagado = golpes; encendido = putts en las mismas celdas + total de putts por nueve); fila del hoyo actual en verde; tocar una celda → ir a ese hoyo en HoleScreenV2 (el dictado a ese jugador se conectará con v2t).
- **Terminado cuando:** putts y totales iguales a v1; el toque lleva al hoyo correcto.

## Paso 6 — `ResultadoV2`: pendientes

- **Leer:** `MoneyTrackerView.swift` (`UnitLogDetailView`), `V2/ResultadoV2.swift`.
- **Crear/Editar:** `V2/ResultadoV2.swift`.
- **Incluye:** tocar Unid → `UnitLogDetailView` (v1); "‹ Hoyo N" regresa al hoyo actual.

## Paso 7 — Auditoría

- **Leer:** `HoleAuditView.swift` (incluye `HoleCorrectionSheet`).
- **Crear/Editar:** primero abrir `HoleAuditView` (v1) desde el semáforo de v2; después `V2/AuditV2.swift` con el mismo guardado.
- **Terminado cuando:** corregir un hoyo desde v2 cambia lo mismo que desde v1.

## Paso 8 — `SetupV2`

- **Leer:** `GuidedSetupView.swift` (`applyCampo`, `applySetup`, `syncStrokes`, pasos 1–4), `PlayerDirectoryView.swift`, `BetCatalog.swift` (plantillas), `REGLAS_SETUP_Y_GOLPES.md` R1, R3, R5, R11, R12.
- **Crear/Editar:** `V2/SetupV2.swift`.
- **Incluye:** pasos 1–3 con el estilo v2 (strokes con ½ y en palabras "ALC recibe 3½ · hoyos 17, 4, 11 y ½ en 2"; pareja base y parejas según el modelo `LaneModel`; quién lleva); paso 4 Apuestas = contenido de v1 embebido; Directorio abre la vista v1.
- **Terminado cuando:** guardar el mismo setup en v1 y v2 produce los mismos strokes, parejas, apuestas y reseteos (R5).

## Paso 9 — `HistorialV2` y `MyHistoryV2`

- **Leer:** `RoundHistoryView.swift` (`RoundHistoryView`, `MyHistoryView`).
- **Crear/Editar:** `V2/HistorialV2.swift`, `V2/MyHistoryV2.swift`.
- **Incluye:** todos los datos de GAP §2.8 y §2.9; "VIGENTE" según decisión de Daniel (pendiente — preguntar antes).

## Paso 10 — Pantallas secundarias

- `UnitLogDetailView`, `CarryB9CardView`, `BetSetupSheet`/`BetsHubView`/editores, `PlayerDirectoryView`: abrir las vistas v1 desde v2 (ya garantiza paridad). Rediseñarlas solo si Daniel lo pide.

---

## Fuera de alcance

Lógica de apuestas, reglas, parser/LLM nuevo, app de Watch, borrar código muerto, renombrar archivos de v1, `GuidedCaptureView` (Siri), `RescueCaptureView`/`FuzzyReviewView` salvo para reutilizarlas.
