# REVISION_DISENO — revisión de accesibilidad y diseño de la Vista v2 (23-oct)

**ESTADO (23-oct, tarde): corregido — ver «Correcciones aplicadas» al final.** Lo de abajo es el hallazgo original.

Qué se revisó: las pantallas de `V2/` y su sistema de estilo `V2/CaddieStyleV2.swift`. Es una revisión por código y por cálculo (no por uso en simulador con tamaños de letra grandes). Nada de esto se ha corregido todavía: son decisiones de diseño de Daniel.

## 1. Tamaño de letra dinámico (Dynamic Type) — NO CUMPLE
- Las 6 tipografías del sistema (`v2Hole` 42, `v2Score` 26, `v2Name` 18, `v2Body` 16, `v2Label` 13, `v2Caps` 12) usan `Font.system(size:)` fijo, y además hay ~50 usos sueltos de `.font(.system(size: …))` en las pantallas (más en `MatchDetailV2`, `SetupV2`, `TarjetaV2`, `MyHistoryV2`). Nada escala con el tamaño de letra del iPhone.
- Filas con altura fija que contienen texto (`TarjetaV2` filas de 52 pt y pie de 40 pt, botones de 44–56 pt): se cortarían con letra grande.
- Ninguna pantalla se adapta a tamaños de accesibilidad (no hay `ViewThatFits`, `@ScaledMetric` ni `dynamicTypeSize`).
- Arreglo propuesto, en este orden: (1) cambiar los 6 tokens a estilos de texto (`v2Body`→`.callout`, `v2Label`→`.footnote`, `v2Caps`→`.caption`, `v2Name`→`.headline`, `v2Score`→`.title2/.title`; `v2Hole` con `@ScaledMetric`), lo que cambia ligeramente el tamaño en el ajuste por defecto; (2) alturas fijas → `minHeight`; (3) en las tablas densas (Tarjeta, Auditoría) limitar el rango con `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` y pasar la fila de jugadores a vertical en tamaños mayores; (4) `ViewThatFits` en las filas −/score/+ de la captura.

## 2. Contraste — CUMPLE EN LO IMPORTANTE, con 3 excepciones
Texto (mínimo 4.5:1): tinta/fondo 15.8, gris secundario/fondo 6.4, verde/blanco 5.4, verde/fondo 4.9, rojo/fondo 5.9, azul/fondo 7.2, dorado oscuro sobre fichas doradas 6.4, blanco sobre verde 5.4, blanco sobre azul 8.0.
Fallan:
- Texto en **naranja del sistema** (advertencia de putts "—p" y "Putts DAN" en la Auditoría): 2.2:1. Usar un naranja oscuro (p. ej. #B45309, ~5:1) o el rojo.
- **Punto naranja del semáforo** de la barra superior: 2.2:1 (un elemento gráfico necesita 3:1); el texto que lo acompaña sí se lee.
- **Bordes dorados punteados** de los botones de Oyes/Unidades: 2.4:1 (necesita 3:1 para delimitar el botón); el texto del botón sí cumple.
Observación: las columnas atenuadas de la Tarjeta (match elegido) quedan a 0.3 de opacidad (~1.6:1) a propósito; es un estado "no participa", no información, pero conviene subirlas a ~0.45.

## 3. VoiceOver — CUMPLE PARCIALMENTE
Bien: botones solo-icono con etiqueta (Setup, Historial, Cerrar ronda, flechas de hoyo, −/+ de la captura y el Setup, fichas de jugador del Evento), celdas de la Tarjeta con descripción completa, filas de Resultado con pista.
Falta:
- Los **−/+ de la hoja de corrección** (`AuditV2`, score y putts) no tienen etiqueta: VoiceOver diría solo "más/menos".
- En **Nota** las fichas de jugador no anuncian cuál está seleccionada.
- El **puntaje de la captura** (`ScoreMarkV2`) se lee como un número suelto: falta "DAN, 4 golpes".
- Los **recuadros azules de strokes** de la Tarjeta no se anuncian como "recibe stroke en este match" (la celda ya describe sus strokes del reparto general).

## 4. Otras observaciones de diseño
- Hay 4 variantes de "chip" de jugador, 20+ separadores y 25 etiquetas en mayúsculas con el mismo código repetido: candidatos a componentes de `CaddieStyleV2` (ya se extrajo `BackButtonV2`).
- La barra de acciones de la captura (semáforo + 3 iconos + Vista v1) y las 5 pestañas inferiores están al límite del ancho en iPhone pequeño; con letra grande se necesitará un menú "más".

## Correcciones aplicadas (23-oct)
**Tamaño de letra.** Los 6 tokens ahora son estilos de texto del sistema (`v2Body`→callout, `v2Label`→footnote, `v2Caps`→caption, `v2Name`→headline, `v2Score`→title2), los ~46 usos sueltos de `.system(size:)` pasaron a estilos, y los textos con tamaño propio (`ScoreMarkV2`, `MoneyTextV2`, `MatchStatusV2`, el número de hoyo con `holeTitleV2()`) usan `@ScaledMetric`. Las alturas fijas con texto son `minHeight`. Límites por pantalla donde hay columnas de ancho fijo: Tarjeta, Resultado, Mi historial y Auditoría crecen hasta XXXL; la captura hasta Accesibilidad 2; la barra inferior hasta XXL. El resto crece sin límite (están en ScrollView). A tamaño por defecto el cambio visible es pequeño (los nombres de 18 a 17 pt y las cifras grandes de 26 a 22 pt). NO se probó en simulador con letra grande: conviene mirarlo en el iPhone con Ajustes › Accesibilidad › Tamaño de letra.
**Contraste.** `CSV2.warning` (#B45309, 5:1) sustituye al naranja del sistema; `CSV2.unitLine` (dorado de bordes y puntos) pasó a #9A6B00 (4.7:1); las columnas atenuadas de la Tarjeta suben de 0.3 a 0.45 de opacidad.
**VoiceOver.** Etiquetas en los −/+ de la hoja de corrección ("Más score", "Menos putts"); el puntaje de la captura se lee "Daniel: 4 golpes" / "sin anotar"; las fichas de jugador (Evento, Nota, quién lleva los strokes) anuncian cuál está seleccionada (`AliasChipRowV2`); la Tarjeta con un match elegido anuncia "recibe stroke en este match".
**Componentes repetidos.** `RowDividerV2`, `capsStyleV2()`, `AliasChipRowV2`, `BackButtonV2`, `moneyStringV2` (19 separadores y 19 etiquetas reemplazados).
