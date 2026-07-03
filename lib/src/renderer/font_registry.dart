import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../layer_canvas_bindings_generated.dart' as bindings;

/// Registers custom fonts (raw TTF/OTF bytes) so a `TextLayer.fontFamily`
/// can reference them by name, instead of always falling back to this
/// package's embedded default font.
///
/// Registration is global to the process — not scoped to a `Scene` or a
/// single `Renderer` — and typically happens once, e.g. during app
/// startup:
///
/// ```dart
/// final data = await rootBundle.load('assets/fonts/Brand-Regular.ttf');
/// FontRegistry.register('Brand', data.buffer.asUint8List());
///
/// final scene = Scene(width: 400, height: 300)
///   ..add(TextLayer(text: 'hello', fontFamily: 'Brand'));
/// ```
class FontRegistry {
  const FontRegistry._();

  /// Registers [data] (raw TTF/OTF bytes) under [name].
  ///
  /// Any `TextLayer` whose `fontFamily` equals [name] renders with this
  /// font from then on. Calling this again with the same [name] replaces
  /// the previously registered font.
  ///
  /// Throws a [FontRegistrationException] if [data] isn't valid font data.
  static void register(String name, Uint8List data) {
    final namePtr = name.toNativeUtf8();
    final dataPtr = calloc<Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      final status = bindings.lc_font_register(
        namePtr.cast(),
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

  /// Removes a font previously registered under [name]. A no-op if no font
  /// was registered under that name.
  static void unregister(String name) {
    final namePtr = name.toNativeUtf8();
    try {
      bindings.lc_font_unregister(namePtr.cast());
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
