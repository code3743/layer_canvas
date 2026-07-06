/// An immutable 32-bit color in ARGB order.
///
/// Named `Color32` rather than `Color` to avoid shadowing `dart:ui`'s `Color`
/// when this package is imported alongside `material.dart`.
///
/// ```dart
/// const red = Color32.fromRGB(255, 0, 0);
/// const semiBlack = Color32(0x80000000); // 50% transparent black
/// ```
class Color32 {
  /// Packed as `0xAARRGGBB`.
  final int value;

  /// Creates a color directly from its packed `0xAARRGGBB` [value].
  const Color32(this.value);

  /// Creates a color from separate alpha/red/green/blue channels, each
  /// `0..255` (values outside that range are masked to the low 8 bits).
  const Color32.fromARGB(int a, int r, int g, int b)
    : value =
          ((a & 0xff) << 24) |
          ((r & 0xff) << 16) |
          ((g & 0xff) << 8) |
          (b & 0xff);

  /// Creates a fully opaque color from separate red/green/blue channels,
  /// each `0..255`.
  const Color32.fromRGB(int r, int g, int b) : this.fromARGB(0xff, r, g, b);

  /// Fully transparent black, `0x00000000`.
  static const transparent = Color32(0x00000000);

  /// Opaque black, `0xff000000`.
  static const black = Color32(0xff000000);

  /// Opaque white, `0xffffffff`.
  static const white = Color32(0xffffffff);

  /// The alpha channel, `0..255`.
  int get alpha => (value >> 24) & 0xff;

  /// The red channel, `0..255`.
  int get red => (value >> 16) & 0xff;

  /// The green channel, `0..255`.
  int get green => (value >> 8) & 0xff;

  /// The blue channel, `0..255`.
  int get blue => value & 0xff;

  /// Opacity of this color alone, in the 0.0-1.0 range.
  double get opacity => alpha / 0xff;

  /// Returns a copy of this color with its alpha channel replaced by [a]
  /// (`0..255`).
  Color32 withAlpha(int a) => Color32.fromARGB(a, red, green, blue);

  /// Returns a copy of this color with [opacity] (`0.0..1.0`) converted to
  /// an alpha channel.
  Color32 withOpacity(double opacity) =>
      withAlpha((opacity.clamp(0.0, 1.0) * 0xff).round());

  @override
  bool operator ==(Object other) => other is Color32 && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Color32(0x${value.toRadixString(16).padLeft(8, '0')})';

  /// Converts to its packed `0xAARRGGBB` [value] — see `Scene.toJson`.
  int toJson() => value;

  /// Reconstructs a [Color32] from [toJson]'s output.
  factory Color32.fromJson(int json) => Color32(json);
}
