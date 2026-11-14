# Entrada de log AIDOG — 2026-11-14 — Release sin GPS (1.0.3) para TestFlight

- **Proyecto/área**: Caddie Score — línea de versión aprobada.
- **Pedido de Daniel**: tener la seguridad de que la versión completa, sin GPS todavía, está resguardada y que de aquí en adelante
  TestFlight se sube desde ella; versión 1.0.3.
- **Auditoría de foco**: dentro (distribución de la versión vigente).
- **Proceso (razonamiento clave)**:
  - La versión completa vivía solo en `gps/cgm` (10 commits sobre `diseno/v2t`, solo en el Mac). Ninguno de esos commits toca GPS y el proyecto
    no referencia el paquete `CaddieGPS`: `717d293` es la versión completa sin GPS.
  - Se crea `release/sin-gps` desde `717d293`, se sube la versión a 1.0.3 (app y reloj deben coincidir) y se archiva desde una copia limpia
    de esa rama para que ningún archivo suelto de GPS entre al build. `gps/cgm` no se sube.
- **Resultado**: ver "Pendientes" (el número de build lo asigna Xcode al subir).
- **Archivos creados/modificados**: `Caddy_Score.xcodeproj/project.pbxproj` (`MARKETING_VERSION` 1.0.2 → 1.0.3 en app y reloj, Debug y Release).
- **Decisiones de Daniel**: subir la versión a 1.0.3; resguardar en GitHub la rama y el tag sin subir `gps/cgm`; subir a TestFlight desde esa marca;
  marcarla como la versión aprobada.
- **Propuestas de Claude no decididas**: dejar `main` apuntando a `release/sin-gps` cuando la versión esté aprobada (reemplaza su commit local de AIDOG,
  ya incluido aquí).
- **Cambios a artefactos** (antes → después · motivo · versión): ninguno. `ESTADO_CS.md` no se edita sin la aprobación expresa de Daniel.
- **Fuentes usadas** (con versión): commit `717d293`; `project.pbxproj`; flujo de `testflight-subida` (archive + exportArchive).
- **Pendientes**:
  - Anotar el número de build real (App Store Connect) y que Daniel apruebe la versión; entonces actualizar `ESTADO_CS.md`.
  - `gps/cgm` sigue solo en el Mac, en desarrollo.
  - `ART_GMM_congruencia_v1.md` sigue sin versionar (no es de este proyecto).
