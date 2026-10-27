# Reorganizar VoiceSheetV2 ("Dictar el hoyo") en 3 zonas

Archivo: `V2/VoiceSheetV2.swift`. Solo es un cambio de layout: no se toca VoiceHolePipeline, ask(), readAloud() ni el flujo de grabación.

## Estructura
1. **Header**: "Hoyo N" + Cerrar. Debajo, una sola línea: "Si dices otro número de hoyo, se cambia solo." (el aviso de cambio de hoyo se queda igual).
2. **Zona 2 · Confirmar lo dictado**
   - Si `draft` está vacío: una fila compacta con el último hoyo anotado ("Hoyo 9 · 4 de 4 anotados ✓").
   - Si hay `draft`: el `reviewCard` actual (así quedaría, messageBox, Empezar de nuevo / Anotar).
   - Siempre: chips "Qué falta" (readAloud(.missing)) y "Contrastar tarjeta ›" (abre ContrastSheetV2; poner chevron para que se vea que navega).
3. **Zona 3 · Preguntar a la tarjeta**: grupos de chips
   - ESTE HOYO: Este hoyo, Unidades, Strokes
   - APUESTAS: Match, Presión, Vuelta, F9, B9
   - ACUMULADO: Cómo vamos, Dinero, Por qué
   - `readbackCard` se dibuja **dentro de su grupo**, justo debajo de los chips del grupo que se tocó (guardar el grupo en un @State). Si la pregunta fue hablada, va arriba de la zona 3.
4. **Barra fija abajo** (`.safeAreaInset(edge: .bottom)`): mic de 64 pt + texto de una línea según `phase` (idle: "Dictar el hoyo" / con draft: "Dictar lo que falta" / recording: "Grabando… toca para detener" / processing: ProgressView). Sacar `controls` del ScrollView.

## Quitar
- Los dos párrafos de ayuda largos; dejar un solo ejemplo corto en la barra del mic.

## No cambiar
- Colores y tipografía de CSV2, minTap 48, dynamicTypeSize hasta accessibility2.
- Acciones de cada chip (mismas llamadas a ask/readAloud).

Mockup: dictar_hoyo_reorganizada.html (pantallas A, B, C).
