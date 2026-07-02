import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

// Blend2D is vendored as a git submodule (third_party/blend2d) and compiled
// directly into this package's native library alongside our own engine
// sources — there is no separate Blend2D build step and no AsmJit.
//
// This is a curated subset of Blend2D's own source manifest (see
// BLEND2D_SRC_LIST in third_party/blend2d/CMakeLists.txt): every non-test
// source file, minus the optional higher-tier SIMD variants (sse3, ssse3,
// sse4_1, sse4_2, avx, avx2, avx2fma, avx512, asimd_crypto). Those tiers
// are gated behind BL_TARGET_OPT_* macros that Blend2D only defines when
// the matching compiler target flags (-mavx2 etc.) are active, which we
// never pass — so omitting their .cpp files is safe, nothing references
// their symbols. The mandatory per-architecture baselines (sse2 on
// x86_64, asimd on arm64) are always included and self-select the same
// way: no manual flags needed.
//
// If the third_party/blend2d pin is ever bumped and upstream adds a new
// source file, it needs to be added here manually — this list is not
// regenerated automatically.
const _blend2dSources = [
    'third_party/blend2d/blend2d/codec/bmpcodec.cpp',
    'third_party/blend2d/blend2d/codec/jpegcodec.cpp',
    'third_party/blend2d/blend2d/codec/jpeghuffman.cpp',
    'third_party/blend2d/blend2d/codec/jpegops.cpp',
    'third_party/blend2d/blend2d/codec/jpegops_sse2.cpp',
    'third_party/blend2d/blend2d/codec/pngcodec.cpp',
    'third_party/blend2d/blend2d/codec/pngops.cpp',
    'third_party/blend2d/blend2d/codec/pngops_asimd.cpp',
    'third_party/blend2d/blend2d/codec/pngops_sse2.cpp',
    'third_party/blend2d/blend2d/codec/qoicodec.cpp',
    'third_party/blend2d/blend2d/compression/checksum.cpp',
    'third_party/blend2d/blend2d/compression/checksum_asimd.cpp',
    'third_party/blend2d/blend2d/compression/checksum_sse2.cpp',
    'third_party/blend2d/blend2d/compression/deflatedecoder.cpp',
    'third_party/blend2d/blend2d/compression/deflatedecoderfast.cpp',
    'third_party/blend2d/blend2d/compression/deflatedecoderutils.cpp',
    'third_party/blend2d/blend2d/compression/deflatedefs.cpp',
    'third_party/blend2d/blend2d/compression/deflateencoder.cpp',
    'third_party/blend2d/blend2d/core/api-globals.cpp',
    'third_party/blend2d/blend2d/core/api-nocxx.cpp',
    'third_party/blend2d/blend2d/core/array.cpp',
    'third_party/blend2d/blend2d/core/bitarray.cpp',
    'third_party/blend2d/blend2d/core/bitset.cpp',
    'third_party/blend2d/blend2d/core/compopinfo.cpp',
    'third_party/blend2d/blend2d/core/context.cpp',
    'third_party/blend2d/blend2d/core/filesystem.cpp',
    'third_party/blend2d/blend2d/core/font.cpp',
    'third_party/blend2d/blend2d/core/fontdata.cpp',
    'third_party/blend2d/blend2d/core/fontface.cpp',
    'third_party/blend2d/blend2d/core/fontfeaturesettings.cpp',
    'third_party/blend2d/blend2d/core/fontmanager.cpp',
    'third_party/blend2d/blend2d/core/fonttagdataids.cpp',
    'third_party/blend2d/blend2d/core/fonttagdatainfo.cpp',
    'third_party/blend2d/blend2d/core/fonttagset.cpp',
    'third_party/blend2d/blend2d/core/fontvariationsettings.cpp',
    'third_party/blend2d/blend2d/core/format.cpp',
    'third_party/blend2d/blend2d/core/glyphbuffer.cpp',
    'third_party/blend2d/blend2d/core/gradient.cpp',
    'third_party/blend2d/blend2d/core/image.cpp',
    'third_party/blend2d/blend2d/core/imagecodec.cpp',
    'third_party/blend2d/blend2d/core/imagedecoder.cpp',
    'third_party/blend2d/blend2d/core/imageencoder.cpp',
    'third_party/blend2d/blend2d/core/imagescale.cpp',
    'third_party/blend2d/blend2d/core/matrix.cpp',
    'third_party/blend2d/blend2d/core/matrix_sse2.cpp',
    'third_party/blend2d/blend2d/core/object.cpp',
    'third_party/blend2d/blend2d/core/path.cpp',
    'third_party/blend2d/blend2d/core/pathstroke.cpp',
    'third_party/blend2d/blend2d/core/pattern.cpp',
    'third_party/blend2d/blend2d/core/pixelconverter.cpp',
    'third_party/blend2d/blend2d/core/pixelconverter_sse2.cpp',
    'third_party/blend2d/blend2d/core/random.cpp',
    'third_party/blend2d/blend2d/core/runtime.cpp',
    'third_party/blend2d/blend2d/core/runtimescope.cpp',
    'third_party/blend2d/blend2d/core/string.cpp',
    'third_party/blend2d/blend2d/core/trace.cpp',
    'third_party/blend2d/blend2d/core/var.cpp',
    'third_party/blend2d/blend2d/geometry/sizetable.cpp',
    'third_party/blend2d/blend2d/opentype/otcff.cpp',
    'third_party/blend2d/blend2d/opentype/otcmap.cpp',
    'third_party/blend2d/blend2d/opentype/otcore.cpp',
    'third_party/blend2d/blend2d/opentype/otface.cpp',
    'third_party/blend2d/blend2d/opentype/otglyf.cpp',
    'third_party/blend2d/blend2d/opentype/otglyf_asimd.cpp',
    'third_party/blend2d/blend2d/opentype/otglyfsimddata.cpp',
    'third_party/blend2d/blend2d/opentype/otkern.cpp',
    'third_party/blend2d/blend2d/opentype/otlayout.cpp',
    'third_party/blend2d/blend2d/opentype/otmetrics.cpp',
    'third_party/blend2d/blend2d/opentype/otname.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/compoppart.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fetchgradientpart.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fetchpart.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fetchpatternpart.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fetchpixelptrpart.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fetchsolidpart.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fetchutilscoverage.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fetchutilsinlineloops.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fetchutilspixelaccess.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fetchutilspixelgather.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/fillpart.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/pipecompiler.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/pipecomposer.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/pipefunction.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/pipegenruntime.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/pipepart.cpp',
    'third_party/blend2d/blend2d/pipeline/jit/pipeprimitives.cpp',
    'third_party/blend2d/blend2d/pipeline/pipedefs.cpp',
    'third_party/blend2d/blend2d/pipeline/piperuntime.cpp',
    'third_party/blend2d/blend2d/pipeline/reference/fixedpiperuntime.cpp',
    'third_party/blend2d/blend2d/pixelops/funcs.cpp',
    'third_party/blend2d/blend2d/pixelops/interpolation.cpp',
    'third_party/blend2d/blend2d/pixelops/interpolation_sse2.cpp',
    'third_party/blend2d/blend2d/raster/rastercontext.cpp',
    'third_party/blend2d/blend2d/raster/rastercontextops.cpp',
    'third_party/blend2d/blend2d/raster/renderfetchdata.cpp',
    'third_party/blend2d/blend2d/raster/rendertargetinfo.cpp',
    'third_party/blend2d/blend2d/raster/workdata.cpp',
    'third_party/blend2d/blend2d/raster/workermanager.cpp',
    'third_party/blend2d/blend2d/raster/workerproc.cpp',
    'third_party/blend2d/blend2d/raster/workersynchronization.cpp',
    'third_party/blend2d/blend2d/support/arenaallocator.cpp',
    'third_party/blend2d/blend2d/support/arenahashmap.cpp',
    'third_party/blend2d/blend2d/support/math.cpp',
    'third_party/blend2d/blend2d/support/scopedallocator.cpp',
    'third_party/blend2d/blend2d/support/zeroallocator.cpp',
    'third_party/blend2d/blend2d/tables/tables.cpp',
    'third_party/blend2d/blend2d/threading/futex.cpp',
    'third_party/blend2d/blend2d/threading/thread.cpp',
    'third_party/blend2d/blend2d/threading/threadpool.cpp',
    'third_party/blend2d/blend2d/threading/uniqueidgenerator.cpp',
    'third_party/blend2d/blend2d/unicode/unicode.cpp',
];

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      language: Language.cpp,
      std: 'c++17',
      defines: {
        // Compile Blend2D without JIT pipeline generation (and therefore
        // without AsmJit): keeps the dependency graph to just Blend2D,
        // avoids executable-memory/W^X concerns on iOS, and is far simpler
        // to get right across five platforms. Blend2D automatically falls
        // back to its reference (non-JIT) pipelines when built this way.
        'BL_BUILD_NO_JIT': null,
        // Blend2D is compiled directly into this library rather than as
        // its own shared library, so its symbols don't need dllexport
        // visibility.
        'BL_STATIC': null,
      },
      includes: ['third_party/blend2d'],
      sources: [
        'src/engine.cpp',
        'src/backend/blend2d/blend2d_backend.cpp',
        ..._blend2dSources,
      ],
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = .ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
