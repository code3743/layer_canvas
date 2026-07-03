/// A single GPS reading plus a capture timestamp — stands in for whatever a
/// real app would read from a geolocation plugin (e.g. `geolocator`'s
/// `Position`) plus `DateTime.now()`. Formatting lives here (not in the
/// scene builder) so that code only ever deals with display strings.
class MockLocation {
  final String placeName;

  /// Degrees, signed: positive is north, negative is south.
  final double latitude;

  /// Degrees, signed: positive is east, negative is west.
  final double longitude;

  final DateTime capturedAt;

  const MockLocation({
    required this.placeName,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
  });

  /// e.g. `48.6959° N, 113.7181° O`.
  String get coordinatesLabel {
    final latHemisphere = latitude >= 0 ? 'N' : 'S';
    final lngHemisphere = longitude >= 0 ? 'E' : 'O';
    return '${latitude.abs().toStringAsFixed(4)}° $latHemisphere, '
        '${longitude.abs().toStringAsFixed(4)}° $lngHemisphere';
  }

  static const _months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  /// e.g. `03 jul 2026 · 09:42 a. m.`.
  String get timestampLabel {
    final day = capturedAt.day.toString().padLeft(2, '0');
    final month = _months[capturedAt.month - 1];
    final hour12 = ((capturedAt.hour + 11) % 12) + 1;
    final minute = capturedAt.minute.toString().padLeft(2, '0');
    final period = capturedAt.hour < 12 ? 'a. m.' : 'p. m.';
    return '$day $month ${capturedAt.year} · '
        '${hour12.toString().padLeft(2, '0')}:$minute $period';
  }
}

/// The mock reading this example renders. A real app would build one of
/// these from `Position` + `DateTime.now()` right before capturing a photo.
final sampleLocation = MockLocation(
  placeName: 'Parque Nacional Glacier, Montana',
  latitude: 48.6959,
  longitude: -113.7181,
  capturedAt: DateTime(2026, 7, 3, 9, 42),
);
