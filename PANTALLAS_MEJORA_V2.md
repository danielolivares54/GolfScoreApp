# Caddy Score - Inventario de Pantallas y Mejoras UX (V2)

Fecha: 2026-04-04

## Objetivo global confirmado
- Todas las pantallas con fondo blanco.
- Pantalla de dictado limpia (sin saturación visual).
- En apuestas individuales no repetir prefijos obvios de `vs`.
- En parejas usar un solo encabezado y listar solo parejas oponentes.
- Abrir módulos desde menú en pantalla completa para evitar overlays comprimidos.

## Flujo principal de navegación
- Pantalla base: `ContentView`.
- Menú inferior: `Dicta`, `Setup`, `F9/B9`, `Money`, `Tarjeta`.
- Modales activos:
  - `Setup` (`GuidedSetupView`)
  - `F9/B9` (`BetZoomCard`)
  - `Money` (`MoneyTrackerView`) en full screen

## Pantallas detectadas

### Núcleo
1. `ContentView` (`Caddy_Score/ContentView.swift:6`)
- Rol: Home + grabación + barra de acciones.
- Mejora V2:
  - Fondo blanco fijo.
  - Reducir elementos visibles durante dictado (modo limpio).
  - Menú claro para abrir cada módulo.

2. `ScorecardView` (`Caddy_Score/ContentView.swift:3945`)
- Rol: Tarjeta principal del juego.
- Mejora V2:
  - Uniformar fondo blanco.
  - Mejor separación por bloques de hoyos/resultados.

3. `ScorecardGrid` (`Caddy_Score/ContentView.swift:5456`)
- Rol: Tabla/retícula de score.
- Mejora V2:
  - Tipografía y espaciado más legibles.
  - Evitar scroll horizontal excesivo en iPhone.

### Setup y configuración
4. `CoursePickerView` (`Caddy_Score/ContentView.swift:307`)
5. `StartHolePickerView` (`Caddy_Score/ContentView.swift:352`)
6. `SetupWizardView` (`Caddy_Score/ContentView.swift:389`)
7. `GuidedSetupView` (`Caddy_Score/ContentView.swift:3227`)
- Mejora V2 común:
  - Fondo blanco.
  - Jerarquía visual simple (secciones claras).
  - Controles más grandes en iPhone.

### Dictado y revisión
8. `FuzzyReviewView` (`Caddy_Score/ContentView.swift:3138`)
- Rol: confirmación de nombres/datos ambiguos.
- Mejora V2:
  - Modo revisión minimalista.
  - Botones primarios grandes y separados.

9. `CardView` (`Caddy_Score/ContentView.swift:5387`)
- Rol: tarjeta pendiente de dictado interpretado.
- Mejora V2:
  - Mostrar primero transcripción.
  - Corrección simple antes de confirmar.

### Resultados y apuestas
10. `BetZoomCard` (`Caddy_Score/ContentView.swift:4560`)
11. `BetZoomStatusCard` (`Caddy_Score/ContentView.swift:3991`)
12. `MatchSummaryView` (`Caddy_Score/ContentView.swift:5275`)
13. `MatchSummaryCard` (`Caddy_Score/ContentView.swift:3974`)
- Mejora V2 común:
  - Fondo blanco.
  - Encabezados y métricas en columnas estables.
  - Evitar chips/botones muy juntos.

14. `MoneyTrackerView` (`Caddy_Score/ContentView.swift:4054`)
- Rol: configuración y wallet de apuestas.
- Estado actual:
  - Ya abre en pantalla completa.
  - Separado en secciones visuales, pero falta simplificar semántica de individual/pareja.
- Mejora V2 concreta:
  - `Individuales`: listar por rival sin `vs` redundante.
  - `Parejas`: un encabezado único + lista de parejas oponentes.
  - `Carry`: visible como campo propio (no oculto en texto compacto).
  - Espaciado táctil mínimo 44pt en botones.

15. `WalletMatchConfigView` (`Caddy_Score/ContentView.swift:4448`)
- Rol: on/off por apuesta en cada match.
- Mejora V2:
  - Reordenar toggles por prioridad de uso.
  - Labels más cortos y claros.

16. `UnitLogDetailView` (`Caddy_Score/ContentView.swift:4508`)
- Rol: detalle de unidades por evento.
- Mejora V2:
  - Tabla simple, fondo blanco, columnas legibles.

## Cambios base recomendados (cross-app)
1. Definir un estilo base `screenBackground = Color.white` para todas las vistas raíz.
2. Estandarizar cards/inputs con padding y altura táctil mínima de 44pt.
3. Evitar modales medianos para módulos complejos: usar full screen.
4. En dictado, usar modo foco:
- Transcripción grande arriba.
- Acciones primarias: Confirmar / Corregir.
- Elementos secundarios colapsados.

## Siguiente implementación sugerida (orden)
1. Unificar fondo blanco en todas las vistas raíz.
2. Rediseñar `ContentView` a home limpio (modo dictado foco).
3. Ajustar `MoneyTrackerView` según reglas Individual/Parejas solicitadas.
4. Ajustar `BetZoomCard` a la maqueta final de resultados.
