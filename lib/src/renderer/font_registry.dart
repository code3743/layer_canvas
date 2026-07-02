import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../layer_canvas_bindings_generated.dart' as bindings;
import '../model/layers/text_layer.dart';

/// Registers custom fonts (raw TTF/OTF bytes) so a `TextLayer.fontFamily`
/// can reference them by name, instead of always falling back to this
/// package's embedded default font.
///
/// A single family [name] can have several [weight]s registered at once —
/// a `TextLayer` with that `fontFamily` renders with whichever registered
/// weight is numerically closest to its own `fontWeight`, so registering
/// e.g. both `TextWeight.normal` and `TextWeight.bold` under `'Brand'` gives
/// every weight in between (and beyond) a reasonable match instead of all
/// collapsing onto a single face.
///
/// Registration is global to the process — not scoped to a `Scene` or a
/// single `Renderer` — and typically happens once, e.g. during app
/// startup:
///
/// ```dart
/// final regular = await rootBundle.load('assets/fonts/Brand-Regular.ttf');
/// final bold = await rootBundle.load('assets/fonts/Brand-Bold.ttf');
/// FontRegistry.register('Brand', regular.buffer.asUint8List());
/// FontRegistry.register(
///   'Brand',
///   bold.buffer.asUint8List(),
///   weight: TextWeight.bold,
/// );
///
/// final scene = Scene(width: 400, height: 300)
///   ..add(TextLayer(text: 'hello', fontFamily: 'Brand'));
/// ```
class FontRegistry {
  const FontRegistry._();

  /// Registers [data] (raw TTF/OTF bytes) under [name] and [weight].
  ///
  /// A `TextLayer` whose `fontFamily` equals [name] renders with whichever
  /// weight registered under that name is closest to its own `fontWeight`.
  /// Calling this again with the same [name] and [weight] replaces just
  /// that variant — other weights already registered under [name] are
  /// unaffected.
  ///
  /// Throws a [FontRegistrationException] if [data] isn't valid font data.
  static void register(
    String name,
    Uint8List data, {
    TextWeight weight = TextWeight.normal,
  }) {
    final namePtr = name.toNativeUtf8();
    final dataPtr = calloc<Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      final status = bindings.lc_font_register(
        namePtr.cast(),
        weight.value,
        dataPtr,
        data.length,
      );
      if (status != 0) {
        throw FontRegistrationException(
          'Failed to register font "$name" (status $status) — the data is '
          'likely not a valid TTF/OTF font.',
        );
      }
    } finally {
      calloc.free(namePtr);
      calloc.free(dataPtr);
    }
  }

  /// Removes the font previously registered under [name] and [weight]. A
  /// no-op if no font was registered under that exact name+weight pair.
  /// Other weights registered under [name] are unaffected.
  static void unregister(String name, {TextWeight weight = TextWeight.normal}) {
    final namePtr = name.toNativeUtf8();
    try {
      bindings.lc_font_unregister(namePtr.cast(), weight.value);
    } finally {
      calloc.free(namePtr);
    }
  }
}

/// Thrown when [FontRegistry.register] is given data the native engine
/// can't parse as a font.
class FontRegistrationException implements Exception {
  final String message;

  FontRegistrationException(this.message);

  @override
  String toString() => 'FontRegistrationException: $message';
}
