# Third-party notices

layer_canvas is an independent project. It is built on top of, but is not
affiliated with, endorsed by, or a wrapper or port of, either of the
projects below.

## Blend2D

Vendored as a git submodule at `third_party/blend2d` and compiled directly
into this package's native library. Blend2D is licensed under a zlib-style
license; see `third_party/blend2d/LICENSE.md` for the full text.

Copyright (c) 2017-2025 Petr Kobalicek, Fabian Yzerman.

## Roboto

The Regular and Bold weights are embedded (base64-encoded) into the native
library so `TextLayer` has a default font with no runtime dependency on the
host platform's fonts. Roboto is licensed under the Apache License,
Version 2.0; see `third_party/fonts/roboto/LICENSE.txt` for the full text.

Copyright 2015 Google Inc.
