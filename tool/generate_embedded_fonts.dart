// Regenerates src/backend/blend2d/fonts/embedded_fonts.h from the static
// Roboto TTFs vendored in third_party/fonts/roboto/.
//
// Run with: dart run tool/generate_embedded_fonts.dart
//
// Why embedded at all: Blend2D has no access to platform font APIs or to
// Flutter's asset bundle — it only knows how to parse font bytes handed to
// it directly. Baking two static weights (regular + bold) straight into the
// native binary means TextLayer works out of the box on every supported
// platform, with no runtime file lookup and no asset-bundling step for
// consumers of this package.
//
// Font bytes are stored base64-encoded (~1.37x the binary size) rather than
// as a `0x12, 0x34, ...` byte array (~6x the binary size once every byte
// becomes a 4-6 character token) — this header ships inside the published
// package, so the encoding overhead is not free. blend2d_backend.cpp decodes
// it once at startup.
import 'dart:convert';
import 'dart:io';

const _fonts = [
  (
    path: 'third_party/fonts/roboto/Roboto-Regular.ttf',
    base64Name: 'kRobotoRegularTtfBase64',
  ),
  (
    path: 'third_party/fonts/roboto/Roboto-Bold.ttf',
    base64Name: 'kRobotoBoldTtfBase64',
  ),
];

const _outputPath = 'src/backend/blend2d/fonts/embedded_fonts.h';
const _charsPerLine = 100;

void main() {
  final buffer = StringBuffer()
    ..writeln('// AUTO GENERATED FILE, DO NOT EDIT.')
    ..writeln('//')
    ..writeln('// Regenerate with: dart run tool/generate_embedded_fonts.dart')
    ..writeln('//')
    ..writeln(
      '// Source fonts: third_party/fonts/roboto/ (Roboto, Apache License 2.0 —',
    )
    ..writeln('// see third_party/fonts/roboto/LICENSE.txt).')
    ..writeln('#ifndef LAYER_CANVAS_BACKEND_BLEND2D_FONTS_EMBEDDED_FONTS_H_')
    ..writeln('#define LAYER_CANVAS_BACKEND_BLEND2D_FONTS_EMBEDDED_FONTS_H_')
    ..writeln()
    ..writeln('// Base64-encoded TTF bytes; see DecodeBase64 in')
    ..writeln('// blend2d_backend.cpp for the decoder.');

  for (final font in _fonts) {
    final base64 = base64Encode(File(font.path).readAsBytesSync());
    buffer
      ..writeln()
      ..writeln('static const char ${font.base64Name}[] =')
      ..write(_formatBase64Literal(base64));
  }

  buffer
    ..writeln()
    ..writeln('#endif  // LAYER_CANVAS_BACKEND_BLEND2D_FONTS_EMBEDDED_FONTS_H_');

  File(_outputPath).writeAsStringSync(buffer.toString());
  stdout.writeln('Wrote $_outputPath');
}

/// Splits [base64] into adjacent C++ string literals (concatenated by the
/// compiler at translation time) so no single line is unreasonably long.
String _formatBase64Literal(String base64) {
  final out = StringBuffer();
  for (var i = 0; i < base64.length; i += _charsPerLine) {
    final end = (i + _charsPerLine < base64.length)
        ? i + _charsPerLine
        : base64.length;
    out.writeln('    "${base64.substring(i, end)}"');
  }
  out.writeln('    ;');
  return out.toString();
}
