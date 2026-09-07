# SSOT — Ontologia y Administracion del Dialogo (V2T Golf Scorecard)

## 0) Objetivo
Controlar el dialogo para llenar la tarjeta con precision. El LLM solo extrae datos; la app administra el flujo, valida y confirma.

---

## 1) Estados del dialogo (maquina de estados)
1. LISTENING — escucha voz
2. TRANSCRIBING — audio -> texto
3. CLASSIFYING — clasifica la intencion
4. PENDING — datos entendidos, esperando confirmacion
5. CONFIRMED — usuario confirma (voz o boton)
6. CORRECTED — usuario corrige o rechaza
7. ERROR — falta algo o hay inconsistencia
8. ADVANCE — siguiente hoyo o consulta

Transiciones:
LISTENING -> TRANSCRIBING -> CLASSIFYING
CLASSIFYING -> PENDING (si hay datos)
PENDING -> CONFIRMED / CORRECTED
ERROR -> LISTENING (pedir lo faltante)

---

## 2) Tipos de utterance (clasificacion)
- VALID_DATA: dato esperado, completo
- INCOMPLETE: falta hoyo, golpes, jugador
- AMBIGUOUS: dos interpretaciones posibles
- NOISE: sin entidad valida
- CORRECTION: "no / corrige / incorrecto"
- CONFIRMATION: "confirmar / correcto / ok"
- QUERY: consulta al sistema
- MATCH_SETUP: jugadores / match
- BETTING / UNITS: apuestas / unidades

---

## 3) Slots (entidades)
Obligatorio por hoyo:
- hoyo
- jugador(es)
- golpes

Opcional:
- putts
- unidades
- tags

---

## 4) Reglas de interpretacion (orden)
1. Si NOISE -> pedir repetir
2. Si CORRECTION -> descartar PENDING
3. Si CONFIRMATION -> guardar PENDING
4. Si VALID_DATA completo -> mostrar tarjeta
5. Si INCOMPLETE -> pedir faltante explicito
6. Si AMBIGUOUS -> pedir confirmacion

---

## 5) Respuestas del sistema (en espanol)
- Falta golpes: "Me falta el numero de golpes."
- Falta jugador: "Que jugador?"
- Falta hoyo: "Que hoyo?"
- Ambiguo: "Dijiste 4 golpes?"
- Confirmacion: "Entendido. Confirma para guardar."

---

## 6) Tarjeta de confirmacion (UI)
Siempre muestra:
- Hoyo (numero real del campo)
- F9/B9
- Par, SI
- Jugadores y golpes

Opcional:
- Putts en vista secundaria

Confirmacion:
- Boton y voz

---

## 7) Log (para entrenamiento)
Cada linea:
[fecha] Accion | Tag | Estado | Match | Transcripcion | Hoyo | Jugadores | Audio

Ejemplos:
- Entendido -> Tag HOLE_ENTRY, Estado PENDIENTE
- Confirmado -> Tag CONFIRM, Estado GUARDADO
- Error -> Tag ERROR, Estado INCOMPLETO

---

## 8) Tags estandar (clasificacion)
- HOLE_ENTRY
- MATCH_SETUP
- UNITS
- PLAYERS
- BETTING
- QUERY
- CONFIRM
- CORRECT
- ERROR

---

## 9) Manejo de ruido
- Si no hay entidades -> NOISE
- Reintentar hasta N veces
- Si sigue fallando -> pedir repetir o dictar claro

---

## 10) Jugadores y base (foursome)
El LLM debe recibir siempre:
- Lista de jugadores del match (alias + nombre)
- Base team / YO (si aplica)

Reglas:
- Nunca asumir jugador si no coincide con alias/nombre
- Si hay ambiguedad -> pedir aclaracion
- Alias deben ser unicos por match
- "Yo" se resuelve contra YO del match (jugador principal)
- "Todos" se expande a todos los jugadores activos del match
- "Los demas" se expande a (todos los jugadores) menos el/los ya mencionados

## 10.1) Correcciones y sobreescrituras
- Si el hoyo ya tiene datos y llega un nuevo registro del mismo hoyo:
  - Preguntar: "Ya existe el hoyo X. Quieres corregirlo?"
  - Solo sobrescribir si confirma

## 10.2) Terminos relativos (birdie/bogey)
- "Birdie/Bogey/Eagle/Doble" requieren par del hoyo
- Se convierte a golpes con logica deterministica (no LLM)

## 10.3) Ambiguedad de nombres
- Si "Ricky" no existe, buscar candidato mas cercano (ej: Ricardo)
- Pedir confirmacion: "Te refieres a Ricardo?"

## 10.4) Ejemplos de frases compuestas
- "Yo 5, los demas 7" -> YO=5, resto de jugadores=7
- "Todos bogey en el hoyo 5" -> todos los jugadores, golpes = par+1

---

## 11) Aprendizaje controlado (vocabulario valido)
El sistema no auto-aprende en caliente.

Mecanismo:
1. Registrar en log los casos "validos no reconocidos".
2. Revisar manualmente el log.
3. Actualizar un archivo de vocabulario/alias aprobado.
4. Reentrenar o ajustar prompts con esa lista aprobada.

Ejemplo de caso:
- Usuario dice "Dani" y no se reconoce. Se agrega como alias valido de DAN.

---

## 12) Decisiones pendientes
1. Confirmacion siempre obligatoria? (recomendado: si)
2. Max jugadores simultaneos en una sola frase?
3. Como manejar birdie/bogey (traduccion a golpes con par)?
