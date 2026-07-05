import 'image_source.dart';
import 'layer.dart';

/// The root of a composition: a fixed-size canvas plus an ordered list of
/// [Layer]s (which may themselves be [Group]s) painted on top of an
/// optional [background].
///
/// [Scene] is a pure data model — it never touches the native renderer.
/// A `Renderer` takes a [Scene] and produces image bytes; that is the only
/// coupling between this model and the rendering backend.
class Scene {
  final int width;
  final int height;

  /// Painted first, before any [layers]. `null` means a transparent canvas.
  LayerImageSource? background;

  final List<Layer> _layers = [];

  Scene({required this.width, required this.height, this.background})
    : assert(width > 0, 'width must be > 0'),
      assert(height > 0, 'height must be > 0');

  /// Layers in insertion order. Stacking order for compositing is
  /// determined by [Layer.zIndex] (stable sort), not by this list's order.
  List<Layer> get layers => List.unmodifiable(_layers);

  void add(Layer layer) => _layers.add(layer);

  void addAll(Iterable<Layer> layers) => _layers.addAll(layers);

  /// Removes the layer with the given [layerId]. Returns whether a layer
  /// was found and removed.
  bool remove(String layerId) {
    final index = _layers.indexWhere((l) => l.id == layerId);
    if (index == -1) return false;
    _layers.removeAt(index);
    return true;
  }

  void clear() => _layers.clear();

  @override
  String toString() =>
      'Scene(${width}x$height, background: $background, '
      'layers: ${_layers.length})';
}
