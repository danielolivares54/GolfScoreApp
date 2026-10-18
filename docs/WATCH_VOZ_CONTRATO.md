# Apple Watch — voz a texto por hoyo: contrato v1 y layout de revisión

Decisiones de la v1 (2026-10-18):

| Tema | Decisión |
|---|---|
| Qué se dicta | **El hoyo completo en una sola dictada**, con todos los jugadores |
| Qué incluye | Golpes, **putts**, **oyes** (orden) y **unidades** (sandy, chip-in, hole out…) |
| Quién interpreta | **El iPhone** (el mismo intérprete de la app). El Watch solo transcribe y muestra la propuesta |
| Quién confirma | El usuario en el Watch (aceptar / avisar) y el iPhone **actualiza ese hoyo** y lo avisa con opción de deshacer |
| Por jugador | Solo como **respaldo**: "Repetir" una fila cuando algo no se entendió |
| Confianza | Umbral **0.80**: `>= 0.80` = `ok`, `< 0.80` = `dudoso`. La propuesta siempre muestra **lo que se va a anotar** con su confianza |

## 1. Por qué todo el hoyo y no por jugador

- Así ya funciona la app: los casos de dictado `C01`, `C04` y `C22`
  (`output/pdf/casos_dictado.json`) son frases de hoyo completo, incluida la mixta
  *"Yo tres, Anselmo cuatro y los demás bogey. Oyes primero Ricardo, segundo Daniel… Daniel hole out."*
- Una sola dictada por hoyo es lo más rápido en cancha; por jugador son 5 dictadas y 5 revisiones.
- Si una parte falla, no se repite todo: se corrige o se repite **solo esa fila**.
- Por eso el intérprete vive en el iPhone: la lógica de alias, "los demás", "yo", correcciones y
  conflictos ya existe en `MatchInterpreter` y no conviene duplicarla en el reloj.

## 2. Flujo

```
Watch                                  iPhone
─────                                  ──────
1. Dicta el hoyo completo
   (dictado del sistema, es-MX)
2. Manda { transcript, hole? } ──────▶ 3. Interpreta con el roster y el hoyo actual
                                          (alias, "los demás", putts, oyes, unidades)
4. Muestra la PROPUESTA  ◀────────────  Devuelve { propuesta, estados, pendientes }
   (layout de la sección 4)
5. Usuario: Aceptar / Corregir /
   Avisar ───────────────────────────▶ 6. Aplica a ESE hoyo (revisión nueva) y muestra
                                          "Hoyo 14 actualizado ✓ · Deshacer"
7. Recibe acuse ("Guardado")  ◀────────
```

Sin iPhone cercano: el Watch guarda la transcripción en cola (`transferUserInfo`) y la propuesta
se genera cuando haya conexión; el hoyo queda como "Pendiente de revisar".

## 3. Mensajes

### 3.1 iPhone → Watch: contexto (siempre actualizado)

`WCSession.updateApplicationContext`, cada vez que cambia el roster, el hoyo actual o las apuestas.

```json
{
  "schema": "caddie.watch.context.v1",
  "round_id": "2026-10-18-CGM",
  "course": "CGM",
  "hole_current": 14,
  "play_order": [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18],
  "holes": [{ "n": 14, "par": 3, "si": 16 }],
  "players": [
    { "alias": "DAN", "name": "Daniel",   "synonyms": ["daniel","dani","danny"], "is_me": true },
    { "alias": "FER", "name": "Fernando", "synonyms": [] }
  ],
  "events_allowed": ["oyes","sandy","chip_in","hole_out"]
}
```

`events_allowed` sale del catálogo (`Resources/catalogo_eventos_caddie.json`). Los eventos
**calculados** (albatros, eagle, birdie, bogey…) los calcula el iPhone con golpes vs par: el reloj
no los manda ni los muestra como unidades.

### 3.2 Watch → iPhone: dictada

```json
{
  "schema": "caddie.watch.dictation.v1",
  "entry_id": "UUID",
  "round_id": "2026-10-18-CGM",
  "hole_hint": 14,
  "transcript": "hoyo catorce daniel tres con dos putts fernando dos los demás cuatro oyes primero fernando segundo roberto tercero daniel cuarto ricardo quinto anselmo sandy ricardo",
  "locale": "es-MX",
  "sent_at": "2026-10-18T15:30:12-06:00"
}
```

### 3.3 iPhone → Watch: propuesta

```json
{
  "schema": "caddie.watch.proposal.v1",
  "entry_id": "UUID",
  "hole": 14,
  "par": 3,
  "overwrites_existing": false,
  "entries": [
    { "alias": "DAN", "strokes": 3, "putts": 2, "status": "ok",     "confidence": 0.96, "heard": "daniel tres con dos putts" },
    { "alias": "FER", "strokes": 2, "putts": null, "status": "ok",  "confidence": 0.93, "heard": "fernando dos" },
    { "alias": "ROB", "strokes": 4, "putts": null, "status": "ok",  "confidence": 0.88, "heard": "los demás cuatro" },
    { "alias": "RIC", "strokes": 4, "putts": null, "status": "ok",  "confidence": 0.88, "heard": "los demás cuatro" },
    { "alias": "ANS", "strokes": 4, "putts": null, "status": "dudoso", "confidence": 0.55, "heard": "los demás cuatro",
      "why": "ya tenía 5 en este hoyo" }
  ],
  "oyes_ranks": { "FER": 1, "ROB": 2, "DAN": 3, "RIC": 4, "ANS": 5 },
  "units": [
    { "event_id": "sandy", "alias": "RIC", "status": "ok", "confidence": 0.91, "heard": "sandy ricardo" }
  ],
  "calculated_preview": [{ "alias": "FER", "event": "birdie" }],
  "unresolved": []
}
```

**Confianza (`confidence`, 0–1) y umbral 0.80:** `>= 0.80` → `ok`; `< 0.80` → `dudoso`. Además,
**siempre** pasa a `dudoso` (aunque la confianza sea alta) un número alto (por ejemplo 12 golpes), una
corrección hablada, sobrescribir un valor ya capturado, o un conflicto de oyes. La confianza la
calcula **el iPhone** en el intérprete (alias exacto vs aproximado, número claro vs ambiguo, "los
demás" vs jugador nombrado), así que no depende de que el reloj entregue confianza por palabra.

Valores de `status`: `ok` (entendido), `dudoso` (hay que confirmarlo: confianza `< 0.80`, número alto, ya
había otro valor, corrección hablada), `falta` (jugador esperado que no se dijo).
`unresolved[]` = lo que no se pudo asignar, con `reason`: `alias_desconocido`, `numero_ambiguo`,
`jugador_ausente`, `oyes_conflicto`, `oyes_fuera_de_par3`, `evento_desconocido`, `ruido`.

### 3.4 Watch → iPhone: decisión

```json
{
  "schema": "caddie.watch.decision.v1",
  "entry_id": "UUID",
  "revision": 2,
  "action": "accept",
  "edits": [{ "alias": "ANS", "strokes": 5, "putts": null }],
  "notify": [{ "text": "anselmo ocho o nueve", "reason": "numero_ambiguo" }]
}
```
`action`: `accept` (aplicar), `notify` (mandar tal cual para resolverlo en el iPhone) o `discard`.
`edits` son las correcciones hechas en el reloj con la Digital Crown. `revision` sube con cada
decisión sobre el mismo `entry_id`; el iPhone aplica solo la mayor (idempotente).

### 3.5 iPhone → Watch: acuse

`{ "entry_id": "...", "result": "applied" | "needs_review" | "rejected", "message": "Hoyo 14 actualizado" }`.

## 4. Layout de revisión en el reloj

Pantalla única con scroll (Digital Crown). Colores del catálogo: ✓ verde `#3F6B4A`, ✗ rojo `#A8462F`,
dudoso en dorado.

1. **Encabezado fijo:** `HOYO 14 · PAR 3`. Si el hoyo ya tenía datos: etiqueta **"Reemplaza"**.
2. **Golpes y putts** — una fila por jugador, en el orden del roster, con **lo que se va a anotar**:
   `DAN   3   ·2p` con un indicador de estado a la izquierda. Las filas `dudoso` muestran además la
   confianza (`62%`) y lo que se escuchó. Lo que se ve en esta pantalla es exactamente lo que el
   iPhone escribirá al aceptar.
   - ✓ **entendido**: tocar abre un selector con la Digital Crown para cambiar golpes o putts.
   - **? dudoso**: se muestra con lo que se escuchó (`heard`) debajo; hay que tocarla para
     confirmarla o corregirla.
   - **− falta**: fila gris "no dijiste a RIC"; se completa con la Crown o con "Repetir".
3. **Oyes** (solo par 3): una línea `1 FER · 2 ROB · 3 DAN · 4 RIC · 5 ANS`, editable. Conflictos
   (dos "primero") o parcial ("lo ganó Anselmo") salen como dudosos.
4. **Unidades:** chips `Sandy RIC`, `Hole out DAN`, etc. Eliminar con deslizar.
5. **Preview calculado** (solo lectura, gris): `FER birdie`, para que sepa que el iPhone lo cuenta solo.
6. **No entendido (✗ rojo):** el texto exacto y su motivo, con **Repetir** (dicta solo esa parte) y
   **Avisar**.
7. **Barra inferior fija:**
   - **Aceptar** (verde): activa cuando no queda nada `dudoso` / `falta` / `unresolved` sin resolver.
     Háptico de éxito.
   - **Avisar** (dorado): manda `notify`; el iPhone abre su pantalla de revisión (`FuzzyReviewView`)
     con lo entendido ya cargado.
   - **Descartar** (gris, con confirmación).

## 5. Qué hace el iPhone al aceptar

1. Si `entry_id` ya se aplicó con `revision` igual o mayor, lo ignora.
2. Aplica **solo a ese hoyo**: `applyHoleEntry` (golpes y putts; 3 y 4 putts generan `3P` / `4P` sin
   unidades), `setOyesRanks(hole:ranksByAlias:)` para oyes y los eventos de unidad manuales.
3. Todo el dinero y los resultados se recalculan solos (se derivan de golpes y eventos).
4. Muestra el aviso **"Hoyo 14 actualizado ✓ · Deshacer"** (guarda el estado previo del hoyo para
   revertir) y manda el acuse al reloj.
5. Si había sobrescritura, el aviso la lista ("ANS 5 → 4").
6. Con `notify`, nada se aplica hasta que el usuario confirma en el iPhone.

## 6. Reglas de validación (las mismas de la app)

- Hoyo 1–18 (`HoleEntryValidator`); golpes > 0; alias que exista en el roster; `putts ≤ strokes`.
- Números altos (por ejemplo 12 golpes) siempre `dudoso`, nunca se reducen a 2 (caso `C09`).
- Oyes solo en par 3 y sin posiciones repetidas; fuera de par 3 es `oyes_fuera_de_par3` (`C16`, `C17`).
- Una corrección hablada ("seis… no, cinco") o reentrada sobre un hoyo ya capturado es `dudoso`
  y pide confirmación (`C11`, `C12`).
- Sin jugador ("hizo cinco y dos putts") no se asigna a nadie: `jugador_ausente` (`C23`).
- Las unidades **no tienen valor monetario** hasta que lo defina la configuración (`C19`, `C21`).

## 7. Pruebas de aceptación

Los 24 casos de `output/pdf/casos_dictado.json` son el conjunto de pruebas: cada `utterance` debe
producir en la propuesta el `expected` del caso, con los estados `dudoso` / `unresolved` donde el
caso dice "pedir confirmación", "preguntar" o "señalar".

## 8. Preguntas que siguen abiertas

1. ~~Umbral de confianza~~ — **resuelto: 0.80** (ver tabla de decisiones).
2. ¿Se permite dictar sin iPhone cerca? El diseño lo soporta con cola; falta decidir si el reloj
   muestra algo mientras tanto.
3. ¿Quién es "yo" cuando dicta otra persona con su Watch (`C06`)? Propuesta: el `is_me` del contexto.
4. Orden de los hoyos: la ronda puede salir del 10 (`C24`); el reloj usa `play_order` del contexto.
5. A verificar al programar el reloj: qué API de dictado se usa en watchOS (el dictado del sistema
   devuelve texto sin confianza por palabra). Con el diseño actual no hace falta, porque la confianza
   se calcula en el iPhone; si más adelante el reloj entrega confianza propia, se combina con la del
   intérprete tomando la menor.
