# Entrada de log AIDOG — 2026-11-14 — Carry, estadística del match, catálogo y activación de AIDOG

- **Proyecto/área**: Caddie Score (rama `gps/cgm`).
- **Pedido de Daniel**:
  1. Cómo opera el Carry en parejas y quién lleva el stroke (con 11 strokes de convenio).
  2. Quitar el anuncio con los nombres de quienes piden el Carry.
  3. Estadística del match en número de hoyos (birdie o menos, par, bogey, doble, triple o más), no porcentual.
  4. Unidades y parejas: el grupo de apuestas (tag) aplica en individual o en parejas y las unidades de cada jugador cuentan
     contra los demás y en su pareja; sin concepto "Parejas" en el catálogo; plantillas sin tocar.
  5. Revisar el skill de AIDOG y usarlo en el proyecto y sus ramas; hacer commit.
- **Auditoría de foco**: parcial — **fuera de alcance vigente** (`ESTADO_CS`: "experiencia durante el match, fuera Setup"):
  catálogo de unidades y directorio (Setup). Daniel los pidió expresamente; no se estacionó nada.
- **Proceso (razonamiento clave)**:
  - El Carry sigue la regla B9-relativa ya acordada: el stroke del Carry se suma o resta a los strokes que ya caen en B9 y la pareja
    que recibía sigue recibiendo. El selector "¿Quién lleva el Carry?" confundía porque solo decidía de qué lado estaba quien pide.
  - Solo se pregunta "¿cuál de los dos lleva el stroke?" cuando el stroke del Carry pasa a la pareja que lo pidió (ninguno recibía).
  - "Tag" = apuestas activas de un match, que salen del catálogo (aclaración de Daniel). Las unidades en parejas ya se rigen por el
    "Unidades" encendido de cada match; se fijó con pruebas.
- **Resultado**: compila; 289 pruebas (287 + 2 nuevas de unidades) en verde; **no probado a mano en pantalla ni en dispositivo**.
- **Archivos creados/modificados**:
  - `Caddy_Score/MatchManager.swift` — `pairCarryNeedsRequesterChoice`; sin strokes en el convenio no se usa un carrier guardado.
  - `V2/MatchDetailV2.swift` — selector del Carry solo cuando el stroke pasa a la pareja que lo pidió; texto "¿Cuál de los dos lleva el stroke del Carry?".
  - `Caddy_Score/RoundHistoryView.swift`, `V2/MyHistoryV2.swift` — cinco categorías en número de hoyos; Acumulado = promedio de hoyos por ronda ± σ.
  - `Caddy_Score/BetCatalog.swift` — "Nueva unidad" (v1) ya no pide Individual/Parejas; sección "Parejas (anteriores)" solo si existen.
  - Pruebas: `MatchDetailV2DataTests`, `MyHistoryDataTests`, `BetSwitchesTests`.
  - AIDOG: `.claude/skills/aidog-gobierno/` (v6), `docs/AIDOG/` (ESTADO_CS, ESTACIONADOS, artefacto ART_CS_admin_archivos, log), `CLAUDE.md`.
- **Decisiones de Daniel**:
  - El Carry lo piden los que pierden; si genera un stroke para la pareja que perdió se define cuál de los dos lo lleva.
  - Estadística del match por número de hoyos con cinco categorías.
  - El catálogo define qué se aplica; el concepto de parejas se elimina; las plantillas no se tocan.
  - Directorio: se deja como está (ya edita strokes, plantilla preferida y tees; se actualiza al cerrar el match).
  - Usar el skill AIDOG en el proyecto y sus ramas; commit autorizado.
- **Propuestas de Claude no decididas**:
  - Zapato cuenta también en parejas (entra como evento de unidad): dejarlo solo individual.
  - Regla de convenio 1: hoy el Carry de quien da ese único stroke se lo pasa a su pareja (B9 queda en 0); según "solo cambia si son 0" no debería.
  - Poder renombrar los tags que trae la app.
- **Cambios a artefactos** (antes → después · motivo · versión): ninguno; `ART_CS_admin_archivos` y `ESTADO_CS` copiados tal cual del borrador de Drive.
- **Fuentes usadas** (con versión): Drive ▸ AIDOG: `aidog-gobierno_v6.skill`, `caddie-score/ESTADO_CS.md`, `caddie-score/ART_CS_admin_archivos.md`; `ESTADO_AIDOG_v4.md`.
- **Pendientes**:
  - Llevar AIDOG y estos cambios a las demás ramas (main, diseno/v2t, diseno/v2-vistas, feature/apuestas-por-rival-y-zoom).
  - `gps/cgm` no está en GitHub; no se hizo push.
  - `ART_GMM_congruencia_v1.md` (dentro del skill) no es de este proyecto: se dejó sin versionar.
  - Probar en iPhone; confirmar el número de build real en App Store Connect (el proyecto está en 1.0.2, build 3 y Xcode lo sube solo).
  - `ESTADO_CS` aún dice "ScoreCaddyAPP, rama principal" y "reglas de apuestas PENDIENTE": actualizar con aprobación de Daniel.
