#ifndef LAYER_CANVAS_BACKEND_BLEND2D_BLEND2D_BACKEND_H_
#define LAYER_CANVAS_BACKEND_BLEND2D_BLEND2D_BACKEND_H_

#include "../backend.h"

#ifdef __cplusplus
extern "C" {
#endif

// The Blend2D implementation of LcGraphicsBackend. Statically compiled in
// for now; see engine.cpp for the single place that selects it.
const LcGraphicsBackend* lc_backend_blend2d(void);

#ifdef __cplusplus
}
#endif

#endif  // LAYER_CANVAS_BACKEND_BLEND2D_BLEND2D_BACKEND_H_
