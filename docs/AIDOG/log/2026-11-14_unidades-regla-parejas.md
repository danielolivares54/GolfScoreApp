# Entrada de log AIDOG — 2026-11-14 — Regla de parejas por unidad y AIDOG en las demás ramas

- **Proyecto/área**: Caddie Score (rama `gps/cgm`).
- **Pedido de Daniel**:
  1. Cada apuesta o unidad trae su regla individual/parejas: lo que gana cada jugador de la pareja cuenta en su pareja si la unidad
     está activa; Skins y Putts no son de parejas por su propia regla; la excepción se define al crear la unidad.
  2. El Zapato cuenta en parejas si el tag de ese match lo tiene activo.
  3. Hacer commit (todo probado), llevar AIDOG a las demás ramas y no subir `gps/cgm` todavía.
- **Auditoría de foco**: fuera de alcance vigente (`ESTADO_CS`: Setup queda fuera; el catálogo de unidades es Setup). Daniel lo pidió.
- **Proceso (razonamiento clave)**:
  - "Tag" = las apuestas activas de un match, tomadas del catálogo (aclaración de Daniel). Cada match (individual o pareja) cuenta las
    unidades según su propio interruptor "Unidades"; esto ya funcionaba y se fijó con pruebas.
  - La regla de parejas vive en la definición de la unidad (`BetDefinition.countsInPairs`): por defecto sí; Skins, Putts y Medal no.
    Al crear una unidad se puede marcar que sea solo individual.
- **Resultado**: compila; 291 pruebas en verde; **no probado a mano en pantalla ni en dispositivo**.
- **Archivos creados/modificados**:
  - `Caddy_Score/MatchManager.swift` — `BetDefinition.countsInPairsOverride` / `countsInPairs`, `unitCodeCountsInPairs`, filtro en el
    total de unidades de la pareja y en su log.
  - `Caddy_Score/BetCatalog.swift` — `individualOnlyTags`, `setCountsInPairs`.
  - `V2/CatalogoV2.swift` — interruptor "Cuenta en parejas" al crear la unidad y en las que crea el usuario; nota "Solo individual" en Skins, Putts y Medal.
  - `Caddy_ScoreTests/CatalogGatingTests.swift` — Zapato en parejas y regla por unidad.
- **Decisiones de Daniel**:
  - La regla individual/parejas es de cada unidad y la excepción se define al definirla.
  - El Zapato cuenta en parejas si el tag del match lo tiene activo (hoy: catálogo encendido y "Unidades" encendido en esa pareja).
  - Plantillas sin tocar; directorio como está.
  - AIDOG va a todas las ramas; `gps/cgm` no se sube todavía.
- **Propuestas de Claude no decididas**:
  - Un interruptor por unidad dentro del tag de cada match (hoy "Unidades" enciende o apaga todas juntas).
  - Poder renombrar los tags que trae la app.
  - Regla de convenio 1 del Carry (si el único stroke cae en F9, el Carry de quien da no debería pasar el stroke a su pareja).
- **Cambios a artefactos** (antes → después · motivo · versión): ninguno.
- **Fuentes usadas** (con versión): código de la rama `gps/cgm` y pruebas; mensajes de Daniel del 2026-11-14.
- **Pendientes**:
  - Subir `gps/cgm` y las ramas con AIDOG cuando Daniel lo diga (no se subió ninguna).
  - Probar en iPhone.
  - `ART_GMM_congruencia_v1.md` sigue sin versionar (no es de este proyecto).
