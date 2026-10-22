# DISENO_V2 — cómo usar estos documentos

Rediseño **solo visual** de Caddie Score. La v1 se queda intacta; la v2 es una vista paralela que se activa con el botón `v2` / `Vista v1`.

## Qué es cada archivo

| Archivo | Para qué sirve | Quién lo usa |
|---|---|---|
| `PROMPT.md` | Las reglas que el agente no puede romper (rama, no tocar lógica, no tocar v1, paridad de datos) | Agente de Xcode — lo lee primero |
| `GAP_ANALISIS.md` | Lista de pantallas v1 → v2, qué falta en cada una (checklist de datos) y **el orden de trabajo** | Agente (qué sigue) y Daniel (revisar avance) |
| `DESIGN_SPEC.md` | Cómo se ve cada pantalla v2: colores, tipografía, componentes, botones | Agente — al construir cada pantalla |
| `CaddieStyleV2.swift` | Componentes compartidos (referencia; la copia viva está en `V2/`) | Agente |
| `PROGRESO.md` | Bitácora del agente + **decisiones de Daniel** (mandan sobre todo lo demás) | Agente escribe, Daniel revisa |

Orden de prioridad si hay conflicto: **PROGRESO (decisiones de Daniel) > GAP_ANALISIS > DESIGN_SPEC > maquetas**.

## Instrucción para el agente de Xcode (copiar y pegar)

> Lee `docs/DISENO_V2/README.md`, luego `PROMPT.md`, `GAP_ANALISIS.md` y `PROGRESO.md`.
> Sigue las reglas de `PROMPT.md`, en especial la regla 8 (paridad de datos: todo dato y acción de la pantalla v1 debe verse en la v2 o a un toque).
> Trabaja en el orden de `GAP_ANALISIS.md` §1. Empieza por `HoleScreenV2` con `EventSheetV2`, `NoteSheetV2` y el hoyo actual compartido entre v1 y v2.
> Al terminar cada pantalla: compila, prueba en simulador con la misma ronda en v1 y v2, marca su checklist en `GAP_ANALISIS.md`, anota en `PROGRESO.md` qué quedó fuera y detente para mi revisión.

## Lo que haces tú (Daniel)

1. Pega la instrucción de arriba en el agente.
2. Al final de cada pantalla: abre v1 y v2 con la misma ronda y compara.
3. Escribe tus decisiones en `PROGRESO.md` (o díselas al agente para que las anote).
4. Responde las 4 decisiones abiertas al final de `GAP_ANALISIS.md`.
