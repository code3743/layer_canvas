import 'image_source.dart';
import 'layer.dart';
import 'serialization.dart';

/// The root of a composition: a fixed-size canvas plus an ordered list of
/// [Layer]s (which may themselves be [Group]s) painted on top of an
/// optional [background].
///
/// [Scene] is a pure data model — it never touches the native renderer.
/// A `Renderer` takes a [Scene] and produces image bytes; that is the only
/// coupling between this model and the rendering backend.
class Scene {
  /// The canvas width, in logical pixels.
  final int width;

  /// The canvas height, in logical pixels.
  final int height;

  /// Painted first, before any [layers]. `null` means a transparent canvas.
  LayerImageSource? background;

  final List<Layer> _layers = [];

  /// Creates an empty canvas of [width] by [height] logical pixels.
  Scene({required this.width, required this.height, this.background})
    : assert(width > 0, 'width must be > 0'),
      assert(height > 0, 'height must be > 0');

  /// Layers in insertion order. Stacking order for compositing is
  /// determined by [Layer.zIndex] (stable sort), not by this list's order.
  List<Layer> get layers => List.unmodifiable(_layers);

  /// Appends [layer] to [layers].
  void add(Layer layer) => _layers.add(layer);

  /// Appends every given layer to this scene's [layers], in order.
  void addAll(Iterable<Layer> layers) => _layers.addAll(layers);

  /// Removes the layer with the given [layerId]. Returns whether a layer
  /// was found and removed.
  bool remove(String layerId) {
    final index = _layers.indexWhere((l) => l.id == layerId);
    if (index == -1) return false;
    _layers.removeAt(index);
    return true;
  }

  /// Removes every layer from [layers].
  void clear() => _layers.clear();

  @override
  String toString() =>
      'Scene(${width}x$height, background: $background, '
      'layers: ${_layers.length})';

  /// Converts to a JSON-safe map. `Layer`/`LayerImageSource`/`LayerPaint`/
  /// `Gradient`/`LayerPath`/etc. all expose their own `toJson`/`fromJson`
  /// pair this recurses into — see [LayerRegistry] for how a custom `Layer`
  /// or `LayerImageSource` subclass round-trips through [fromJson] too.
  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    'background': background?.toJson(),
    'layers': [for (final layer in _layers) layer.toJson()],
  };

  /// Reconstructs a [Scene] from [toJson]'s output, via [LayerRegistry].
  factory Scene.fromJson(Map<String, Object?> json) {
    final backgroundJson = json['background'] as Map<String, Object?>?;
    final scene = Scene(
      width: json['width'] as int,
      height: json['height'] as int,
      background: backgroundJson == null
          ? null
          : LayerRegistry.decodeImageSource(backgroundJson),
    );
    final layersJson = json['layers'] as List<Object?>;
    scene.addAll([
      for (final layerJson in layersJson)
        LayerRegistry.decodeLayer(layerJson as Map<String, Object?>),
    ]);
    return scene;
  }
}
