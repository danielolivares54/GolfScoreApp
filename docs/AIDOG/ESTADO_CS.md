# ESTADO_CS — Caddie Score (BORRADOR)
> Copiar a ScoreCaddyAPP/docs/AIDOG/ESTADO_CS.md. Cambia solo con aprobación de Daniel.

**Objetivo**: App de marcador y apuestas de golf operada por voz en el campo; actualizar la tarjeta en un intento, "como lápiz y goma".

**Alcance vigente**: experiencia del jugador durante el match (fuera: setup).
Sub-frente: GPS caddie láser (v1 sin mapas, voz a demanda, yardas).

**Fuentes de verdad**:
- Repo ScoreCaddyAPP (/Users/danielolivares/Developer/Caddy_Score) — rama principal
- Specs: docs/WATCH_EXPERIENCIA_MATCH_SPEC.md, docs/DISENO_V2/REORG_VOICESHEET_V2.md
- Datos de campo: archivo de cancha (CGM) + GolfCourseAPI
- Reglas de apuestas: definidas por Daniel (PENDIENTE)

**Roles**:
- Daniel: dueño del producto y probador en campo
- Claude chat: análisis, specs, tester
- Claude agente en Xcode: implementación (solo con spec aprobada) y admin de archivos

**Artefactos**:
- ART_CS_admin_archivos (borrador, en esta carpeta)
- ART_CS_regresion_v1 (ESTACIONADO): correcciones de la ronda del 24-sep como pruebas pasa/no pasa
- ART_CS_spec_pantalla_v1 (candidato)

**Decisiones abiertas**: reconfigurar apuestas; valores y símbolos de unidades; reglas de oyes en par 3; lista completa de unidades manuales.

**Regla de foco**: un cambio de app entra solo si sale de una ronda real o de una decisión abierta; ideas nuevas → ESTACIONADOS.md.

**Estructura en el repo**:
```
docs/AIDOG/
├── ESTADO_CS.md
├── ESTACIONADOS.md
├── log/          (AAAA-MM-DD_tema.md)
├── artefactos/   (ART_CS_*)
└── pruebas/      (regresión de rondas reales)
```
