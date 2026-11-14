# Protocolo de validación (AIDOG)

## Validación cruzada entre modelos
1. Un modelo genera el artefacto (o Daniel lo escribe).
2. Otro modelo (Gemini, DeepSeek, ChatGPT) lo ejecuta con el System Prompt pegado.
3. Ambas salidas se contrastan **contra la fuente de verdad**, no solo entre sí.
4. Si discrepan → decide la fuente. Si coinciden → muestrea al menos un punto contra la fuente (puede ser error compartido).

## Conjunto de prueba (regresión)
- Cada artefacto tiene casos con resultado esperado conocido.
- Una versión nueva se acepta solo si no empeora ningún caso que la anterior acertaba.
- Limitación a declarar siempre: si el resultado esperado lo produjimos nosotros (no un experto humano), el artefacto puede aprender nuestros errores.

## Privacidad
No enviar datos identificables a modelos externos:
- Salud/seguros: datos de asegurados, diagnósticos, montos por episodio.
- Fiscales (SAT): RFC, CURP, razón social de terceros, UUID y contenido de CFDI, montos de declaraciones, e.firma, CIEC o contraseñas (estas últimas nunca, ni a Claude).

Para validación cruzada usar solo el prompt con casos anonimizados, y respetar lo que permita el contrato con el cliente.

## Registro de fallos
Cada fallo va al log: caso · qué esperaba · qué salió · regla cambiada · versión resultante.
