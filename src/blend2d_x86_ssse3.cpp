// MSVC does not define __x86_64__/__i386__ (it uses _M_X64/_M_IX86), and it
// does not need per-function target attributes: its intrinsics are usable in
// any function regardless of the baseline. So the guard accepts both
// spellings, and the clang-only `#pragma clang attribute` is skipped there.
#if defined(__x86_64__) || defined(__i386__) || defined(_M_X64) || defined(_M_IX86)

#ifndef BL_TARGET_OPT_SSSE3
#define BL_TARGET_OPT_SSSE3
#endif

#if defined(__clang__)
#pragma clang attribute push(__attribute__((target("ssse3"))), apply_to=function)
#endif // __clang__
#include "../../third_party/blend2d/blend2d/core/pixelconverter_ssse3.cpp"
#if defined(__clang__)
#pragma clang attribute pop
#endif // __clang__

#endif // x86 / x86_64
