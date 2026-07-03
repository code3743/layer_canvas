#if defined(__x86_64__) || defined(__i386__)

#ifndef BL_TARGET_OPT_SSSE3
#define BL_TARGET_OPT_SSSE3
#endif

#pragma clang attribute push(__attribute__((target("ssse3"))), apply_to=function)
#include "../../third_party/blend2d/blend2d/core/pixelconverter_ssse3.cpp"
#pragma clang attribute pop

#endif // __x86_64__ || __i386__
