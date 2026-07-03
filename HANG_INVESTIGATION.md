# Problema: Blend2D no carga en Android (y posiblemente iOS) dentro de Flutter

## Objetivo

Tener el motor nativo (`layer_canvas`, Dart FFI + Blend2D) renderizando
realmente un `RectangleLayer` end-to-end **dentro de una app Flutter** en
Android e iOS (no solo en `dart test` sobre el host macOS), como parte de la
Etapa 5 del proyecto (serialización Scene→nativo + primer render real desde
Dart). El código Dart (`Renderer`, `Scene`, `RectangleLayer`) y el puente FFI
(`lc_render_scene`, `LcLayerDesc`) ya están implementados y funcionan; lo que
falta es lograr que el motor nativo cargue y corra dentro del runtime de una
app real, no solo en pruebas de consola.

## Estado actual

- **En el host (`dart test`, VM de Dart en macOS):** funciona perfecto e
  instantáneo. `lc_render_scene` compone capas, exporta PNG válido, todos los
  tests pasan (31/31). Verificado visualmente (PNG con rectángulos con
  rotación, ancla, escala, esquinas redondeadas y stroke, todo correcto).
- **Dentro de Flutter en Android:** `lc_image_create` (la primera llamada
  nativa a Blend2D) se cuelga indefinidamente. Confirmado en:
  - Emulador API 36.1 (preview)
  - Emulador API 34 (estable)
  - Dispositivo físico Samsung SM-A217M
- **Dentro de Flutter en iOS:** en investigación, sin conclusión firme. El
  build de Xcode compila bien (Blend2D compila sin errores para
  `arm64-apple-ios`), pero no se pudo confirmar si el mismo cuelgue ocurre
  ahí, por una cadena de problemas de tooling no relacionados al bug en sí:
  falta de Developer Mode en el dispositivo, certificado de desarrollador
  sin confiar, Rosetta 2 faltante para `iproxy` (herramienta de Flutter para
  el puente USB del VM Service de Dart), y espacio en disco agotándose
  repetidamente durante los intentos. El último intento se detuvo a pedido
  del usuario, quien va a probar directamente desde VS Code.

## Evidencia recolectada (Android)

1. El proceso **no crashea** — queda vivo, bloqueado (confirmado con
   `kill -3` vía `run-as`, sin crash/tombstone en logcat).
2. La librería `liblayer_canvas.so` **nunca aparece mapeada** en
   `/proc/PID/maps` del proceso, ni siquiera tras 5+ minutos de espera real.
   Solo `libflutter.so` está cargado (confirmado comparando tamaños de las
   regiones `r-xp` mapeadas a `base.apk`).
3. Se descartó, con evidencia directa, que sea:
   - **JIT/AsmJit de Blend2D**: ya compilado con `BL_BUILD_NO_JIT`
     (deshabilitado desde el diseño original de la Etapa 4).
   - **`mmap`/`userfaultfd`**: el único `mmap` en todo Blend2D es para mapeo
     de archivos (`core/filesystem.cpp`), no alcanzable desde el camino de
     código de `lc_image_create`.
   - **La auto-inicialización estática de Blend2D**
     (`BLRuntimeInitializer` / `__attribute__((init_priority(102)))`): se
     deshabilitó por completo (comentando la instancia global
     `bl_runtime_auto_init`) y se reemplazó por una llamada manual a
     `bl_runtime_init()` al inicio de nuestra propia función `Create()`. El
     síntoma fue **idéntico** — ni siquiera el primer log dentro de
     `Create()` llegó a imprimirse.
4. Se instrumentó código con logs en dos mecanismos distintos (para
   descartar que fuera un problema de captura de logs, no del código):
   - `fprintf(stderr, ...)` con `fflush` explícito.
   - `__android_log_print` resuelto en tiempo de ejecución vía
     `dlsym(RTLD_DEFAULT, "__android_log_print")` (evita tener que linkear
     `-llog` en `hook/build.dart`, lo cual casi rompe el build al intentar
     detectar la plataforma target desde Dart).

   Archivos instrumentados:
   - `third_party/blend2d/blend2d/core/runtime.cpp` (macro `LC_LOG`/
     `LC_TRACE`, un log antes de cada llamada `_rt_init` dentro de
     `bl_runtime_init()`).
   - `src/backend/blend2d/blend2d_backend.cpp` (macro `LC_LOG`, logs en
     `Create()`).

   **Ningún log aparece nunca en logcat**, ni el primerísimo
   (`"Create: entered"`, literalmente la primera línea de la función).
   Combinado con el punto 2 (`.so` nunca mapeado), esto confirma que el
   cuelgue ocurre **en el propio `dlopen()`** de la librería (~1.4MB, con
   Blend2D completo estáticamente linkeado vía `BL_STATIC`), antes de que
   cualquier código nuestro o de Blend2D reciba control.

## Hipótesis descartadas (con evidencia)

- JIT/AsmJit — descartado (ya deshabilitado de fábrica).
- `mmap`/página cero (`userfaultfd`) — descartado (no alcanzable desde este
  código).
- Auto-init estático de Blend2D (`init_priority`) — descartado (se quitó y
  el síntoma no cambió).
- Que fuera la imagen del emulador (preview vs. estable) — descartado
  (mismo cuelgue en API 34 estable, en dos emuladores distintos, y en un
  dispositivo físico Samsung real).
- Que fuera "solo lento, no colgado" — descartado (se esperó 5+ minutos
  reales sin ningún progreso).

## Causa raíz identificada y resuelta

**`thread_local` en Blend2D crea un segmento PT_TLS en el `.so`**, lo que
provoca que `dlopen()` se cuelgue en Android.

### Mecanismo exacto

`third_party/blend2d/blend2d/threading/uniqueidgenerator.cpp:78` declara:

```cpp
static thread_local uint64_t tls_id_state[uint32_t(Domain::kMaxValue) + 1];
```

Esto emite un segmento `PT_TLS` en `liblayer_canvas.so`. Cuando Android's
bionic llama a `dlopen()` sobre esa librería:

1. Adquiere el lock global del enlazador (`g_dl_mutex`).
2. Para procesar el segmento TLS, necesita actualizar los slots TLS de cada
   hilo ya existente (Flutter crea al menos 5 hilos — UI, raster, IO, GPU,
   y el threadpool de Dart — antes de que Native Assets cargue la librería).
3. Esta actualización requiere señalizar/suspender esos hilos. Si alguno está
   bloqueado o en un estado de señales bloqueadas, `dlopen()` espera
   indefinidamente bajo el lock.
4. La librería nunca termina de mapearse → el `.so` nunca aparece en
   `/proc/PID/maps` → ningún código nuestro recibe control.

Esto explica todos los síntomas:
- El proceso no crashea (está bloqueado en el lock, no en código).
- La librería nunca se mapea.
- Ningún log aparece (ninguna función de la librería fue ejecutada).
- El comportamiento es idéntico con o sin `BLRuntimeInitializer`
  (eso era un red herring — el cuelgue ocurre antes de que cualquier
  inicializador estático corra).

### Fix aplicado

En `hook/build.dart`, se agrega la define:

```dart
'BL_BUILD_NO_TLS': null,
```

Blend2D ya tiene soporte explícito para esto (`api-build_p.h` línea 46
documenta `BL_BUILD_NO_TLS`). Con esta define, `uniqueidgenerator.cpp` cae
al path atómico simple (sin `thread_local`), eliminando el segmento `PT_TLS`
del `.so`. El fallback usa `std::atomic<uint64_t>` — correcto y más que
suficientemente rápido para nuestro caso de uso.

Adicionalmente, se revirtieron todos los cambios de diagnóstico:
- `src/backend/blend2d/blend2d_backend.cpp`: eliminados LC_LOG, dlsym para
  android log, y la llamada manual a `bl_runtime_init()`.
- `example/lib/main.dart`: eliminada `_diagnosticClearOnly()`, restaurado el
  uso de `Renderer().render(scene)`.
- `third_party/blend2d/` (submodule): sin cambios (estaba limpio).

## Cambios que SÍ quedan bien (parte real de la Etapa 5, no diagnóstico)

- `src/scene_desc.h`: formato de intercambio `LcLayerDesc`/`LcLayerKind`,
  compartido entre `engine.h` y `backend.h`.
- `src/engine.h`/`engine.cpp`: función pública `lc_render_scene`.
- `src/backend/backend.h`: entrada `render_layers` en la tabla de funciones
  del backend.
- `src/backend/blend2d/blend2d_backend.cpp`: función `RenderLayers` (además
  de los logs temporales) que aplica transform (posición/rotación/
  escala/ancla) y pinta rectángulos con relleno/contorno/esquinas
  redondeadas — **validado correcto visualmente en el host**.
- `lib/src/ffi/layer_descriptor.dart`: traduce un `Layer` de Dart a un
  `LcLayerDesc` nativo.
- `lib/src/renderer/renderer.dart`: clase pública `Renderer` con
  `render()`/`renderToFile()`.
- `test/renderer_test.dart`: pruebas end-to-end del `Renderer` (pasan todas
  en el host).
