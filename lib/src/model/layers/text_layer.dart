import '../color.dart';
import '../layer.dart';

/// Horizontal alignment of text within its bounding box.
enum TextAlignment { left, center, right }

/// Font weight on the standard 100–900 CSS/OpenType scale.
///
/// Named `TextWeight` rather than `FontWeight` to avoid shadowing `dart:ui`'s
/// `FontWeight` when imported alongside `material.dart`.
class TextWeight {
  final int value;

  const TextWeight._(this.value);

  static const thin = TextWeight._(100);
  static const light = TextWeight._(300);
  static const normal = TextWeight._(400);
  static const medium = TextWeight._(500);
  static const semiBold = TextWeight._(600);
  static const bold = TextWeight._(700);
  static const black = TextWeight._(900);

  @override
  String toString() => 'TextWeight($value)';
}

/// A run of styled text rendered as a layer.
///
/// When no [size] is given, the native backend uses the laid-out text bounds
/// as the intrinsic size. [fontFamily] falls back to the backend's default
/// system font when `null`.
class TextLayer extends Layer {
  final String text;
  final String? fontFamily;
  final double fontSize;
  final Color32 color;
  final TextAlignment align;
  final TextWeight fontWeight;

  TextLayer({
    required this.text,
    this.fontFamily,
    this.fontSize = 14.0,
    this.color = Color32.black,
    this.align = TextAlignment.left,
    this.fontWeight = TextWeight.normal,
    super.id,
    super.transform,
    super.size,
    super.opacity,
    super.zIndex,
    super.visible,
  });

  @override
  String get type => 'text';

  @override
  Map<String, Object?> get properties => {
    'text': text,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'color': color,
    'align': align.name,
    'fontWeight': fontWeight.value,
  };
}
