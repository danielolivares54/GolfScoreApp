# Caddie Score — Lista de cambios v2

Origen: uso real en ronda (septiembre 2026). Complementa el `CLAUDE.md` del handoff de diseño.

## Cómo trabajar esta lista

1. Antes de modificar nada, inspecciona el proyecto existente y dime qué archivo/vista corresponde a cada punto.
2. Implementa **un punto a la vez**, en el orden de prioridad de abajo. Al terminar cada uno, dime qué archivos cambiaste y cómo probarlo en el simulador.
3. Si un punto choca con el código actual o es ambiguo, **pregunta antes de suponer**. No inventes reglas de apuesta.
4. Los puntos marcados **[BLOQUEADO]** no se implementan hasta que Daniel confirme la regla.

## Prioridad

| Orden | Puntos | Motivo |
|---|---|---|
| 1 | 6 | Único punto que pierde datos |
| 2 | 1, 2, 17, 20 | Afectan el cálculo de la apuesta |
| 3 | 3, 4, 5, 7, 9, 10, 11 | Información que hoy no se ve |
| 4 | 12, 13, 14, 15, 16, 19 | Detalle y explicación |
| 5 | 8 | Voz |
| — | 18 | [BLOQUEADO] |

---

## Reglas generales

**1. Strokes enteros.** No existen 0.5 strokes. El stepper avanza de 1 en 1, el modelo usa `Int`, y los datos guardados con decimales se redondean o se rechazan con un aviso.
- Aceptación: no hay forma de capturar ni mostrar un stroke fraccionario.

**2. Strokes con signo por jugador.** En cada match los strokes se muestran desde la perspectiva del jugador: `+N` si los recibe y `−N` si los da; `0` si no hay. Hoy desaparecen los que el jugador da.
- Aceptación: en un match A vs B con 2 strokes para B, A ve `−2` y B ve `+2`.

**3. F9 y B9 siempre visibles.** Toda pantalla con golpes o resultados muestra subtotal F9, subtotal B9 y total. **Corrección (2026-09-26): F9/B9 NO son literal hoyos 1–9 / 10–18.** F9 = los primeros 9 hoyos jugados, empezando en el hoyo de salida marcado en el Setup; B9 = los segundos 9. Si se sale en el hoyo 10, F9 son los hoyos 10→18 y B9 son 1→9. Todas las pantallas deben indexar por orden de juego (`MatchManager.playOrder()`/`segmentForHole`), nunca por número literal de hoyo. Si B9 no se ha jugado se muestra vacío, no se oculta.

**4. Todos los jugadores siempre.** Ninguna pantalla recorta, filtra o salta jugadores. Si no caben a lo ancho, scroll horizontal. En foursome se muestran los 4.

**5. Resultado completo.** Se muestran todas las cifras del match, p. ej. `5 3 1`, no `5 · dos presiones`. Cada presión lleva su valor propio.

**6. Cerrar ronda explícito.** La ronda persiste aunque la app se cierre o el sistema la mate. Borrar y pasar resultados solo ocurre con un botón **Cerrar ronda** y diálogo de confirmación.
- Aceptación: capturar 3 hoyos, forzar cierre de la app, reabrir → los 3 hoyos siguen ahí.

## Scorecard

**7. Resumen inferior completo.** Hoy la parte inferior no muestra resúmenes, se salta un jugador y solo despliega 3. Debe mostrar el resultado de todos los jugadores.

**8. Voz.** El reconocedor confunde "par" con "bar", "por", etc.
- El input manual (+ / −) es el método principal y no se quita.
- Pasar al reconocedor (`SFSpeechAudioBufferRecognitionRequest.contextualStrings`) las palabras del campo `voz` del catálogo y los nombres de los jugadores.
- Aceptar también números dictados ("cuatro") como golpes.

## Tarjeta

**9. Deslizar F9 / B9.** La tarjeta se desliza horizontalmente entre F9 y B9 (paginado), con subtotales en cada página.

**10. Símbolos siempre.** Cada celda muestra el símbolo del evento según el catálogo (punto 20), en todo momento.

## Resultados

**11. Todos los jugadores.** Ver punto 4; hoy faltan jugadores en esta pantalla.

**12. Zoom al tocar.** Tocar un resultado abre su detalle: strokes con signo, F9, B9, total y cada presión de ese match.

**13. Corte de oyes.** Explicar el corte de los oyes: qué oyes hubo, en qué hoyo, quién lo ganó y cuántas unidades vale.

## Unidades

**14. Detalle de unidad.** Al tocar una unidad se lista cada registro: hoyo, jugador, tipo de evento, y si ganó (verde `#3F6B4A`) o perdió (rojo `#A8462F`).

**15. Botón de unidad.** Abre una lista con scroll solo de las **unidades manuales** del catálogo (`unidades_manuales`), no de las calculadas.

**16. Catálogo único.** La lista de birdie, eagle, etc. es la misma para todos los jugadores y sale del catálogo (punto 20), nunca por jugador.

## Setup parejas

**17. Quién recibe los strokes.** En cada combinación de parejas se elige, de entre los 4 jugadores, quién recibe los strokes, y cuántos (entero).

## Apuestas

**18. [BLOQUEADO] Reconfigurar apuestas.** Los tipos de apuesta y su cálculo se definen en una sesión aparte. No modificar la lógica de apuestas hasta recibir la especificación.

## Audit

**19. Comentarios sobre datos.** El audit comenta sobre los datos capturados (inconsistencias, valores fuera de rango, strokes que no cuadran), **no** avisa de hoyos que faltan por jugar.

## Catálogo de eventos

**20. Leer eventos del catálogo.** Eventos, símbolos, colores, unidades y palabras de voz se leen de `catalogo_eventos_caddie.json`, no se escriben en el código. Ver sección siguiente.

---

## Integración del catálogo

Ubicación: `Resources/catalogo_eventos_caddie.json`, incluido en el target de la app (Target Membership marcado).

Modelo sugerido (ajustar al estilo del proyecto):

```swift
struct CatalogoEventos: Codable {
    let version: Int
    let eventosCalculados: [EventoCalculado]
    let unidadesManuales: [UnidadManual]

    enum CodingKeys: String, CodingKey {
        case version
        case eventosCalculados = "eventos_calculados"
        case unidadesManuales = "unidades_manuales"
    }
}

struct EventoCalculado: Codable, Identifiable {
    let id: String
    let nombre: String
    let reglaDiffPar: ReglaDiff      // Int o ">=2"
    let simbolo: String
    let color: String
    let unidades: Int?               // nil = por confirmar
    let voz: [String]
    enum CodingKeys: String, CodingKey {
        case id, nombre, simbolo, color, unidades, voz
        case reglaDiffPar = "regla_diff_par"
    }
}

struct UnidadManual: Codable, Identifiable {
    let id: String
    let nombre: String
    let descripcion: String
    let soloHoyosPar: [Int]?
    let unidades: Int?
    let requiere: [String]
    let voz: [String]
    enum CodingKeys: String, CodingKey {
        case id, nombre, descripcion, unidades, requiere, voz
        case soloHoyosPar = "solo_hoyos_par"
    }
}
```

- `regla_diff_par` puede ser un número (`-1`) o un texto (`">=2"`): `ReglaDiff` debe decodificar ambos.
- Si `unidades` es `null`, el evento se muestra pero **no suma unidades** y se marca "valor por confirmar".
- Símbolos: `circulo`, `circulo_doble`, `circulo_triple`, `cuadro`, `cuadro_doble`, `ninguno` — dibujarlos con SwiftUI shapes.
- Cada unidad registrada guarda: `id_evento`, `hoyo`, `jugador`, `contra_jugador`, `unidades`, `origen` (`calculado` | `manual`).

## Preguntas abiertas (preguntar a Daniel, no suponer)

1. Valor en unidades de cada evento (campos `null`).
2. Si los símbolos coinciden con los acordados.
3. ~~Si birdie/eagle se calculan con golpes brutos o netos.~~ **Resuelto (2026-09-24):** birdie/águila (eagle) se calculan con golpes **brutos**; ya está definido así en el código/catálogo, confirmado por Daniel.
4. Lista completa de unidades manuales.
5. Money Tracker: explicar a Daniel qué calcula hoy y de dónde sale cada columna (V/P/C/M) **antes** de cambiarlo.
