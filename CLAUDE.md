# Caddy_Score

Responde en español.

## Gobierno AIDOG (skill `aidog-gobierno` y artefacto `ART_CS_admin_archivos`)

Este proyecto y todas sus ramas usan el skill de AIDOG (`.claude/skills/aidog-gobierno/`, versión v6) y el artefacto
`docs/AIDOG/artefactos/ART_CS_admin_archivos.md`. Estado y log del proyecto: `docs/AIDOG/` (copia de Drive ▸ AIDOG ▸ caddie-score).

- Al inicio de cada sesión lee `docs/AIDOG/ESTADO_CS.md` y la última entrada de `docs/AIDOG/log/`; resume en 3 líneas.
- Clasifica cada pedido: SUMA / APRENDIZAJE / DESVÍA. Si desvía, una línea: "⚠️ Desvío: [tema]. ¿Estacionar o cambiar foco?" y
  agrégalo a `docs/AIDOG/ESTACIONADOS.md` solo si Daniel estaciona. Avisos de una línea, nunca sermones.
- Nunca borres docs: lo obsoleto se marca OBSOLETO en el encabezado. `ESTADO_CS.md` cambia solo con aprobación de Daniel.
- Al cerrar trabajo sustantivo propón una entrada de log (`docs/AIDOG/log/AAAA-MM-DD_tema.md`, plantilla en
  `.claude/skills/aidog-gobierno/assets/LOG_entrada_plantilla.md`); se escribe solo si Daniel la aprueba. Cada commit
  referencia su entrada de log. El commit pide confirmación de Daniel.
- Una decisión de Daniel que no está en el log se avisa (W5); un "ok" ambiguo ante una acción con efecto se confirma (W4).
