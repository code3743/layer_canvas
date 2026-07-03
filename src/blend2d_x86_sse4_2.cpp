#if defined(__x86_64__) || defined(__i386__)

#ifndef BL_TARGET_OPT_SSE4_2
#define BL_TARGET_OPT_SSE4_2
#endif

// Both files pull in simd/simd_p.h transitively, which contains PCLMUL
// inline helpers. The attribute must cover pclmul even for files that don't
// use it directly, otherwise Clang rejects the __builtin_ia32_pclmulqdq128
// calls emitted by the inline expansion.
#pragma clang attribute push(__attribute__((target("sse4.2,pclmul"))), apply_to=function)
#include "../../third_party/blend2d/blend2d/opentype/otglyf_sse4_2.cpp"
#include "../../third_party/blend2d/blend2d/compression/checksum_sse4_2.cpp"
#pragma clang attribute pop

#endif // __x86_64__ || __i386__
