# Cambios 2026-10-18 — Carry, dinero y pantalla de Resultados

Rama: `feature/apuestas-por-rival-y-zoom`. Estado: compila; probado en simulador (iPhone 17) con una
ronda demo de 18 hoyos; **falta probarlo en iPhone con una partida real**.

## 1. Reglas de apuestas (lo que quedó decidido)

### Carry
- **Quién lo pide:** solo quien perdió el F9 (si el F9 empata, nadie puede pedirlo).
- **Desde dónde cuenta:** siempre desde el primer hoyo de B9 (hoyo 10 en una ronda que sale del 1),
  aunque se active después.
- **Qué ajusta:** el stroke del que lo pide, ±1, dentro de B9:
  - Si el solicitante **recibía N** strokes en B9 pasa a N+1: el stroke nuevo es la **ventaja N+1**
    (siguiente hoyo por Stroke Index entre los 9 hoyos de B9).
  - Si **daba N** pasa a dar N−1: se **quita la ventaja N** (la última).
  - Los demás strokes no se mueven. B9 y Carry son idénticos hasta el hoyo del cambio.
  - Si no había strokes de ese lado, el stroke lo lleva quien pidió el carry.
- **Cómo se paga:** es una apuesta aparte de B9, con la **apuesta original** (no lleva Doble B9):
  1 unidad de vuelta (gane por lo que gane) + 1 unidad de presión por cada presión abierta.
  Ej. `5 3 1` = vuelta + 2 presiones. Es la misma regla que cualquier apuesta.
- Carry y Ajuste 50 son excluyentes (SSOT sección 7). Carry y Doble B9 son independientes.
- Carry se restaura al reabrir la app (antes se perdía porque se validaba la elegibilidad antes de
  tener los scores).

### Dinero
- **F9 / B9:** vuelta + presión de cada segmento. Doble B9 duplica la vuelta y la presión de B9.
- **Match:** 1 unidad (gana/pierde la suma de los 18 hoyos). **Solo se cobra con los 18 hoyos
  capturados por todos** (`MatchManager.isRoundComplete()`).
- **Unidades:** unidades de campo (birdie, sandy, chip-in…) **+ oyes**. Antes los oyes no entraban a
  la U del dinero.
- Los valores de apuesta de una plantilla se copian al match; al guardar la plantilla ahora se
  re-sincronizan con el match en curso (`refreshBetValues(fromTemplate:)`). `setVueltaValue` ahora
  guarda en disco.

## 2. Pantallas

- **Resultado:** ahora solo la **Tabla** (`MatchResumenView`, spec `Caddie_MatchResumen_spec`):
  F9, B9 (×2 con Doble), Match, Carry (solo si está activo), Unidades y Total con "X paga a Y".
  Tocar una fila despliega el detalle y un enlace al zoom de ese concepto.
- La **tarjeta anterior está desactivada** (no borrada): `legacyResultCardEnabled = false` en
  `ContentView.swift`, con comentario. Poner `true` la vuelve a mostrar.
- **Tarjeta Carry B9** (`CarryB9CardView`): ventaja (strokes en B9 normal → carry, hoyo y número de
  ventaja), resultado B9 vs Carry (vuelta, presiones, dinero) y tabla hoyo por hoyo con los dos
  resultados y acumulados. Se abre desde la fila Carry o desde el banner "Ver tarjeta Carry ›".
- **Zoom B9** y **tarjeta de hoyo a hoyo:** muestran en dorado cómo cambia el resultado con carry
  (`C +1`), el stroke del carry resaltado y el acumulado con carry.
- **Log de unidades:** suma campo + oyes en un solo Total, con desglose `Campo +n · Oyes +n`.
  Desde la Tabla abre F9 + B9 juntos.
- **Arranque:** se quitó la imagen `LaunchLogo` de la pantalla de arranque
  (`Caddy-Score-Info.plist`): medía 1280 pt de ancho y se veía con zoom.

## 3. Archivos principales

| Archivo | Qué cambió |
|---|---|
| `MatchManager.swift` | Strokes del carry dentro de B9, dinero del carry, F9/B9 por separado, match a 18 hoyos, oyes en unidades, `carryCardData`, `carryAccumByHole`, restauración del carry, demo de 18 hoyos (DEBUG) |
| `ContentView.swift` | Tabla como vista única, zooms por fila, carry resaltado, log de unidades por segmento |
| `MoneyTrackerView.swift` | `MatchResumenView`, `CarryB9CardView`, desglose del log de unidades |
| `BetCatalog.swift` | La edición de plantilla propaga los valores al match |
| `Caddy-Score-Info.plist` | Pantalla de arranque sin imagen |

## 4. Cómo probar en el simulador

Ronda demo de 18 hoyos (solo Debug): ejecutar con el argumento `-demo18 YES`
(`MatchManager.loadDemo18()`, golpes de DAN/ROB y de B9 tomados de capturas reales; el resto
inventado). Valores: vuelta/presión/match 50, unidad 25.

## 5. Pendientes

1. Edición del valor de la apuesta **dentro del zoom** de cada fila (guardar por match, no por
   plantilla; los rivales individuales tienen valores propios que ganan sobre los globales).
2. Probar todo con una partida real en iPhone.
3. El selector de carry de pareja (RIC | ANS) no re-asigna un carry ya activo.
4. Módulo de voz del Apple Watch: ver `docs/WATCH_VOZ_CONTRATO.md`.
