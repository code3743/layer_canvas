import '../color.dart';
import '../layer.dart';

/// Horizontal alignment of text within its bounding box.
enum TextAlignment { left, center, right }

/// Font weight on the standard 100–900 CSS/OpenType scale.
///
/// Named `TextWeight` rather than `FontWeight` to avoid shadowing `dart:ui`'s
/// `FontWeight` when imported alongside `material.dart`.
class TextWeight {
  /// The raw 100–900 CSS/OpenType weight value.
  final int value;

  const TextWeight._(this.value);

  /// Creates a weight directly from its raw 100–900 value — mainly for
  /// [fromJson]; prefer one of the named constants above when the weight is
  /// a compile-time constant.
  factory TextWeight.fromValue(int value) => TextWeight._(value);

  /// Weight 100.
  static const thin = TextWeight._(100);

  /// Weight 300.
  static const light = TextWeight._(300);

  /// Weight 400 — the default.
  static const normal = TextWeight._(400);

  /// Weight 500.
  static const medium = TextWeight._(500);

  /// Weight 600.
  static const semiBold = TextWeight._(600);

  /// Weight 700.
  static const bold = TextWeight._(700);

  /// Weight 900.
  static const black = TextWeight._(900);

  @override
  String toString() => 'TextWeight($value)';

  /// Converts to its raw [value] — see `Scene.toJson`.
  int toJson() => value;
}

/// A run of styled text rendered as a layer.
///
/// When no [size] is given, the native backend uses the laid-out text bounds
/// as the intrinsic size. [fontFamily] falls back to the backend's default
/// system font when `null`.
class TextLayer extends Layer {
  /// The text to render.
  final String text;

  /// Name of a font registered via `FontRegistry.register`, or `null` to
  /// use the backend's default system font.
  final String? fontFamily;

  /// Font size, in the [Scene]'s logical pixel space.
  final double fontSize;

  /// The text color.
  final Color32 color;

  /// Horizontal alignment within [Layer.size].
  final TextAlignment align;

  /// Font weight; when [fontFamily] is set, the registered weight closest
  /// to this one is used.
  final TextWeight fontWeight;

  /// Creates a text layer showing [text].
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

  @override
  Map<String, Object?> toJson() => {
    ...commonJson(),
    'properties': {
      'text': text,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'color': color.toJson(),
      'align': align.name,
      'fontWeight': fontWeight.toJson(),
    },
  };

  /// Reconstructs a [TextLayer] from [toJson]'s output.
  factory TextLayer.fromJson(Map<String, Object?> json) {
    final common = parseCommonLayerJson(json);
    final properties = json['properties'] as Map<String, Object?>;
    return TextLayer(
      id: common.id,
      transform: common.transform,
      size: common.size,
      opacity: common.opacity,
      zIndex: common.zIndex,
      visible: common.visible,
      text: properties['text'] as String,
      fontFamily: properties['fontFamily'] as String?,
      fontSize: (properties['fontSize'] as num).toDouble(),
      color: Color32.fromJson(properties['color'] as int),
      align: TextAlignment.values.byName(properties['align'] as String),
      fontWeight: TextWeight.fromValue(properties['fontWeight'] as int),
    );
  }
}
