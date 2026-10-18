# Encargo: app de Apple Watch para Caddie Score (módulo de voz por hoyo)

Documento para entregar al agente/desarrollador que construirá la app del reloj.
**La app del iPhone (Caddie Score) queda congelada** en el tag `freeze-pre-watch-2026-10-18`; el reloj
se desarrolla aparte y se conecta a ella con WatchConnectivity.

Adjuntar también: `docs/WATCH_VOZ_CONTRATO.md` (mensajes JSON, estados, reglas de validación),
`Caddy_Score/output/pdf/casos_dictado.json` (24 frases de prueba) y
`Caddy_Score/Resources/catalogo_eventos_caddie.json` (eventos y colores).

## 1. Qué es y qué no es

- **Es:** una app de watchOS companion del iPhone. El jugador dicta **un hoyo completo** (golpes,
  putts, oyes y unidades de todos los jugadores), el reloj muestra **lo que se va a anotar** con su
  confianza, y el jugador **acepta, corrige o avisa**. El iPhone interpreta y aplica.
- **No es:** un intérprete. El reloj no calcula apuestas ni birdies, ni decide alias: transcribe,
  manda el texto y pinta la propuesta que devuelve el iPhone.
- **Datos de la ronda** (roster, hoyo actual, par): vienen del iPhone en `application context`.

## 2. Requisitos técnicos

- watchOS 26 (el iPhone corre iOS 26+), SwiftUI, sin Combine (usar `async/await`).
- Bundle del iPhone: `comDOG.Caddy-Score`; el reloj es su companion (`comDOG.Caddy-Score.watchkitapp`).
- `WatchConnectivity`: `updateApplicationContext` (iPhone → reloj), `sendMessage` (cuando el iPhone
  está alcanzable) y `transferUserInfo` (cola confiable cuando no lo está).
- Dictado: el del sistema, `es-MX`. Verificar qué API se usa en watchOS; el diseño **no depende** de
  confianza por palabra (la calcula el iPhone).
- Háptico: `WKInterfaceDevice.current().play(.success)` al aceptar, `.failure` al rechazar.
- Capa de transporte detrás de un protocolo (`WatchBridge`) con una implementación **mock** que lee
  los casos de dictado, para poder desarrollar y probar sin el iPhone.
- Accesibilidad: Dynamic Type, VoiceOver en cada fila (alias, golpes, putts, estado), contraste
  suficiente en los tres estados.

## 3. Pantallas

Medidas de referencia: 45 mm (≈ 198×242 pt). Todo scrolleable con Digital Crown.
Colores: entendido `#3F6B4A`, error `#A8462F`, dudoso dorado `#C79B3C`, fondo `#F5F6F2` / oscuro del
sistema.

### 3.1 Inicio
```
┌────────────────────┐
│ CGM · Sale en H1   │
│  HOYO 14   PAR 3   │   ← hoyo actual (del contexto)
│                    │
│   ┌────────────┐   │
│   │  DICTAR    │   │   ← botón grande
│   └────────────┘   │
│  Pendientes: 1  ›  │   ← solo si hay hoyos en cola
└────────────────────┘
```
Tocar el hoyo permite cambiarlo (Crown). Sin contexto del iPhone: "Abre Caddie Score en el iPhone".

### 3.2 Dictando
```
┌────────────────────┐
│  HOYO 14           │
│  ● Escuchando…     │
│                    │
│ "daniel tres con   │   ← transcripción en vivo
│  dos putts fernan… │
│                    │
│  [ Terminar ]      │
└────────────────────┘
```

### 3.3 Interpretando
`Interpretando…` con indicador; si pasa de ~8 s: "Seguimos esperando al iPhone" y botón
**Guardar en cola**.

### 3.4 Revisión (la pantalla principal)
```
┌────────────────────┐
│ HOYO 14 · PAR 3    │   ← "Reemplaza" si el hoyo ya tenía datos
├────────────────────┤
│ ✓ DAN   3   ·2p    │   ← entendido
│ ✓ FER   2          │
│ ✓ ROB   4          │
│ ? ANS   4   62%    │   ← dudoso: confianza + lo escuchado
│   "los demás cuatro│
│ − RIC  falta       │   ← no se dijo
├────────────────────┤
│ OYES 1FER 2ROB 3DAN│
│      4RIC 5ANS     │
├────────────────────┤
│ UNIDADES           │
│ [Sandy RIC]        │
│ (birdie FER: auto) │   ← solo lectura, lo calcula el iPhone
├────────────────────┤
│ ✗ No entendí:      │
│ "anselmo ocho o    │
│  nueve"            │
│ [Repetir] [Avisar] │
├────────────────────┤
│ [ACEPTAR] [Avisar] │   ← barra fija
└────────────────────┘
```
Reglas:
- Una fila por jugador en el orden del roster, con **el valor que se va a anotar**.
- `ok` ✓ cuando la confianza es `>= 0.80`; `dudoso` ? cuando es menor (se muestra el %) o cuando
  el iPhone lo marca por regla (número alto, corrección hablada, sobrescritura, conflicto de oyes).
- **Aceptar** solo se habilita cuando no queda ninguna fila `dudoso`, `falta` o `unresolved` sin
  resolver (confirmarla con un toque cuenta como resolverla).
- **Avisar** manda todo con lo dudoso marcado; el iPhone abre su pantalla de revisión.
- **Descartar** (menú ⋯) con confirmación.

### 3.5 Editar una fila
```
┌────────────────────┐
│ ANS · HOYO 14      │
│      GOLPES        │
│   ▲   4   ▼        │   ← Digital Crown cambia el valor
│      PUTTS         │
│   ▲   —   ▼        │
│ [Listo]  [Quitar]  │
└────────────────────┘
```
Rango: golpes 1–15, putts 0–`golpes`. Un valor ≥ 10 sigue marcado dudoso hasta que se confirme.

### 3.6 Oyes (solo par 3)
Lista ordenada de los 5 jugadores con ① al ⑤; tocar uno y moverlo con la Crown, o "Quitar oyes".
Posiciones repetidas se marcan en rojo y bloquean **Aceptar**.

### 3.7 Resultado
- **Guardado ✓** "Hoyo 14 actualizado" (háptico de éxito) y vuelve a Inicio con el hoyo siguiente.
- **Revisar en iPhone** (dorado): lo mandado quedó en revisión.
- **Rechazado** (rojo) con el motivo que devuelva el iPhone.

### 3.8 Sin conexión
Banner "iPhone no disponible · se enviará al reconectar"; el hoyo queda en **Pendientes** con su
transcripción. Pendientes muestra la lista y permite reintentar o descartar.

## 4. Estados de la app del reloj

`inicio → dictando → interpretando → revisión → (aceptado | avisado | descartado) → resultado`
y `revisión → repetir parte → interpretando`. Cada transición conserva el `entry_id` del hoyo;
cada decisión nueva sobre el mismo hoyo sube `revision`.

## 5. Criterios de aceptación

1. Con el mock, los 24 casos de `casos_dictado.json` producen la propuesta esperada (`expected`) y
   los estados `dudoso` / no entendido donde el caso lo pide.
2. **Aceptar** no se habilita con filas dudosas pendientes.
3. Una corrección con la Crown actualiza la fila y se envía en `edits`.
4. Reenviar el mismo `entry_id` y `revision` no duplica nada (idempotente).
5. Sin iPhone cercano el hoyo queda en cola y se envía solo al reconectar.
6. Se ve bien en 41, 45 y 49 mm, en claro y oscuro, con Dynamic Type grande.
7. Las filas se leen con VoiceOver: "Daniel, 3 golpes, 2 putts, entendido".

## 6. Lo que falta en la app del iPhone (fase siguiente, NO incluido en el freeze)

El iPhone todavía no tiene el puente con el reloj. Hace falta:

1. `WatchBridge` (`WCSessionDelegate`): activar la sesión y empujar el contexto.
2. Recibir `dictation.v1`, correr `MatchInterpreter` con el roster y el hoyo, y construir
   `proposal.v1` con confianza y estados.
3. Recibir `decision.v1`: aplicar al hoyo (`applyHoleEntry`, `setOyesRanks`, eventos de unidad),
   guardar el estado previo para **Deshacer**, mostrar "Hoyo N actualizado ✓" y mandar el acuse.
4. Abrir `FuzzyReviewView` cuando la decisión sea `notify`.
5. Pruebas con los 24 casos de dictado.

## 7. Entregables esperados del reloj

Proyecto/target de watchOS, `WatchBridge` + mock, las pantallas 3.1–3.8, fixtures JSON de al menos
cinco propuestas (limpia, con dudosos, con no entendido, par 3 con oyes, con sobrescritura) y un
README corto de cómo correrlo con y sin iPhone.
