# Apple Watch — voz a texto por hoyo: contrato y layout de revisión

Objetivo: el Watch dicta un hoyo, lo digitaliza, **muestra lo que entendió** y el jugador lo
**acepta** o **avisa lo que no se entendió** antes de mandarlo al iPhone. Este documento define lo
que el iPhone espera recibir y cómo debe verse la revisión en el reloj.

## 1. Qué debe saber el Watch (iPhone → Watch)

Se manda con `WCSession.updateApplicationContext` cada vez que cambia el roster o el hoyo:

```json
{
  "schema": "caddie.watch.context.v1",
  "round_id": "2026-10-18-CGM",
  "course": "CGM",
  "hole_current": 14,
  "holes": [{ "n": 14, "par": 3, "si": 16 }],
  "players": [
    { "alias": "DAN", "name": "Daniel",   "synonyms": ["daniel","dani","danny"] },
    { "alias": "FER", "name": "Fernando", "synonyms": [] }
  ],
  "events_allowed": ["oyes","sandy","chip_in"]
}
```
`events_allowed` sale de `catalogo_eventos_caddie.json` (unidades manuales). Los eventos
**calculados** (albatros, eagle, birdie, bogey…) **no los manda el reloj**: el iPhone los calcula
con golpes vs par.

## 2. Qué entrega el Watch por hoyo (Watch → iPhone)

`WCSession.transferUserInfo` (cola confiable) y, si el iPhone está alcanzable, `sendMessage`.

```json
{
  "schema": "caddie.watch.hole.v1",
  "entry_id": "UUID",            // idempotencia: reenviar el mismo hoyo no duplica
  "revision": 2,                 // cada corrección aceptada sube la revisión; gana la mayor
  "round_id": "2026-10-18-CGM",
  "hole": 14,
  "sent_at": "2026-10-18T15:30:12-06:00",
  "transcript": "hoyo catorce daniel tres fernando dos oyes fernando uno",
  "locale": "es-MX",
  "accepted_by_user": true,
  "entries": [
    { "alias": "DAN", "strokes": 3, "putts": 2, "status": "ok",     "confidence": 0.97 },
    { "alias": "FER", "strokes": 2, "putts": null, "status": "dudoso", "confidence": 0.62,
      "heard": "fernando dos" }
  ],
  "units": [
    { "event_id": "sandy",   "alias": "DAN", "status": "ok",     "confidence": 0.9 }
  ],
  "oyes_ranks": { "FER": 1, "ROB": 2, "DAN": 3, "RIC": 4, "ANS": 5 },
  "notes": ["penalidad en el 14 de ROB"],
  "unrecognized": [
    { "text": "anselmo ocho o nueve", "reason": "numero_ambiguo" }
  ]
}
```

Campos y valores:
- `status` de cada elemento: `ok` (se entendió), `dudoso` (se entendió pero con baja confianza o
  hay alternativas), `falta` (se esperaba un jugador y no se dijo).
- `unrecognized[].reason`: `alias_desconocido`, `numero_ambiguo`, `hoyo_ausente`, `evento_desconocido`,
  `ruido`.
- `oyes_ranks` solo en hoyos par 3, con **todos** los jugadores de la ronda (1 = más cerca). El oyes
  de pareja y el individual se calculan en el iPhone a partir de estos rankings.
- `putts`: 3 y 4 putts generan los eventos `3P` / `4P` (sin unidades) en el iPhone.

### Validación (mismas reglas que el iPhone, `HoleEntryValidator`)
- hoyo 1–18; `strokes > 0`; alias que exista en el roster; `putts ≤ strokes`; `oyes_ranks` solo si par = 3
  y sin rankings repetidos.
- Un hoyo con elementos `dudoso`/`falta`/`unrecognized` **no se manda como aceptado** sin que el usuario
  lo confirme: se manda con `accepted_by_user: false` y el iPhone lo abre en su pantalla de revisión.

## 3. Layout de revisión en el reloj

Pantalla única con scroll (Digital Crown), de arriba a abajo:

1. **Encabezado:** `HOYO 14 · PAR 3` y el texto dictado (2 líneas, "ver todo" al tocar).
2. **Entendido (verde ✓):** una fila por jugador: `DAN  3  (2p)`. Tocar abre un selector con la
   Digital Crown para corregir golpes o putts.
3. **Dudoso (dorado ?):** mismas filas, con lo que se escuchó (`heard`) debajo. Hay que tocarlas
   para confirmarlas o corregirlas; no se pueden aceptar en bloque.
4. **No entendido (rojo ✗):** el texto exacto que no se pudo interpretar y su motivo.
   Dos botones por línea: **Repetir** (dicta solo esa parte) y **Avisar** (se manda como
   `unrecognized` para resolverlo en el iPhone).
5. **Unidades / Oyes (si aplica):** chips con el evento y el jugador; en par 3, el orden de oyes
   `1 FER · 2 ROB · 3 DAN…` editable.
6. **Barra inferior fija:**
   - **Aceptar** (verde): activo cuando no quedan elementos `dudoso` ni `falta` sin resolver.
     Manda `accepted_by_user: true` y vibra con háptico de éxito.
   - **Avisar** (dorado): manda el hoyo tal cual, con todo lo dudoso/no entendido marcado,
     `accepted_by_user: false`. El iPhone lo abre para revisión.
   - **Descartar** (gris, con confirmación).

Estados de cada fila: `ok` ✓ verde (#3F6B4A) · `dudoso` ? dorado · `falta` − gris · `error` ✗ rojo
(#A8462F), los mismos colores del catálogo.

## 4. Qué hace el iPhone al recibirlo

1. Descarta si `entry_id` ya se aplicó con una `revision` igual o mayor.
2. `accepted_by_user: true` y sin `unrecognized`: aplica directo.
   - `entries` → `MatchManager.applyHoleEntry(HoleEntryData(...))`
   - `units` → eventos de unidad manuales (`upsertUnitEvent`)
   - `oyes_ranks` → `setOyesRanks(hole:ranksByAlias:)`
3. `accepted_by_user: false` o con `unrecognized`: abre `FuzzyReviewView` con lo entendido ya
   cargado y el texto crudo, y notifica al usuario. Nada se aplica hasta confirmar.
4. Devuelve al Watch un acuse (`ack: entry_id, applied | needs_review`) para que el reloj muestre
   "Guardado" o "Revisar en iPhone".

## 5. Preguntas abiertas (para cerrar antes de programarlo)

1. ¿El reloj dicta **todo el hoyo de una vez** (todos los jugadores) o un jugador a la vez?
2. ¿Qué umbral de confianza separa `ok` de `dudoso`? Propuesta: `< 0.80` = dudoso.
3. ¿Los oyes se capturan en el reloj o solo en el iPhone?
4. ¿Se permite modo sin iPhone cercano? (la cola de `transferUserInfo` lo soporta; los avisos de
   revisión llegarían después).
5. ¿Idioma de dictado fijo `es-MX` o con apodos por jugador? (los sinónimos viajan en el contexto).
