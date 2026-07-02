import '../color.dart';
import '../layer.dart';

enum TextAlignment { left, center, right }

/// A simplified, backend-agnostic font weight (mirrors the standard
/// 100-900 CSS/OpenType weight scale).
///
/// Named `TextWeight` rather than `FontWeight` on purpose: `dart:ui` (and
/// therefore every Flutter app) already exports a `FontWeight`, and this
/// package is meant to be imported unprefixed alongside `material.dart`.
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

/// A run of text laid out and painted as a single layer.
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
