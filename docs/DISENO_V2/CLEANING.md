# CLEANING — pendientes de limpieza y de catálogo (no bloquean la v2)

Anotado el 21-oct a pedido de Daniel. Nada de esto se toca hasta que él lo decida; la v2 sigue su plan.

## A. Duplicados / limpieza visual
1. **Carry duplicado en Resultado.** Resultado muestra el dinero del Carry en la línea de detalle de cada match ("Carry +$100"), y el detalle del match vuelve a mostrar la tarjeta/estado del Carry (concepto Carry, botones y enlace "Ver tarjeta Carry"). Daniel lo ve repetido: decidir en cuál de los dos lugares queda y quitar el otro. (Pendiente de aclarar con Daniel cuál conserva.)

## B. Catálogo de apuestas (el "tag" de apuestas) — revisión del 21-oct

**Dónde se edita hoy:** solo en la v1 y por un camino largo: ⚙ Setup → botón "Apuestas" → página "Catálogo" (`GuidedSetupView` → `BetsHubView` → `BetDefinitionEditorView`). Desde la v2 se llega igual (⚙ abre el Setup de la v1), pero no hay un acceso directo ni diseño v2.

**Qué sí permite el editor:** activar/desactivar cada tag (interruptor), cambiar cuántas unidades vale (stepper) y agregar una unidad nueva manual (nombre, tipo Individual/Parejas, valor). El alcance de la apuesta de putts (F9/B9/18/Vuelta) también se edita ahí.

**Lo que NO está resuelto:**
1. **Los interruptores de Oyes, Oyes Parejas y Match Parejas no hacen nada.** Ninguna regla de `MatchManager` consulta si esos tags están activos: Oyes y parejas se calculan siempre. Daniel dice que Oyes Parejas y Match Parejas no son indispensables → deben poder apagarse de verdad (decisión pendiente: ocultar la sección/la tarjeta de Oyes de parejas y el match de parejas cuando estén apagados).
2. **El valor "Vale" de Oyes se ignora.** El Oyes vale siempre 1 unidad (`oyesUnitForHole` solo usa un valor por hoyo que pone la voz; el catálogo no se lee).
3. **No se puede borrar ni renombrar una unidad creada.** `BetDefinitionStore.remove` existe pero el editor no lo expone; tampoco hay edición de nombre.
4. **Unidades manuales de tipo Parejas se pueden crear pero no se pueden capturar:** las pantallas de captura solo listan unidades manuales individuales.
5. **Solo existen dos modos de captura** (manual = un toque, calculado = sale del score). Un tercer tipo "por input" (contador/paso numérico) no existe; las calculadas nuevas requieren código (no son editables por datos). Daniel mencionó Sandy par, Green en regulación y Birdie en el 18 como ejemplos de unidades que se definen y se activan en el tag: Sandy par y Green en regulación entrarían como manuales (ya se pueden crear); Birdie en el 18 ya existe como calculada (B18).
6. Una unidad manual desactivada conserva sus eventos ya anotados en el match (siguen contando); solo deja de ofrecerse.
7. Cambiar el catálogo no recalcula el match en curso hasta volver a Setup (`setupDefaultBets()` al cerrar el Setup).

**Propuesta para cuando se haga la edición** (a decidir con Daniel): un acceso "Catálogo" propio en la v2 (desde la hoja Unidades y desde el Setup), con interruptores que sí apliquen a Oyes/Parejas, borrar/renombrar unidades, y capturar unidades de parejas.
