part of '../../amap_native_plugin.dart';

class AmapLatLng {
  const AmapLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() {
    return <String, Object?>{'latitude': latitude, 'longitude': longitude};
  }
}

class AmapCircleGeofence {
  const AmapCircleGeofence({
    required this.center,
    required this.radiusMeters,
    this.strokeColor = const Color(0xFF2563EB),
    this.fillColor = const Color(0x332563EB),
    this.strokeWidth = 2,
  });

  final AmapLatLng center;
  final double radiusMeters;
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  /// Returns whether [point] is inside or on this circular geofence.
  bool contains(AmapLatLng point) {
    const earthRadiusMeters = 6378137.0;
    final latitude1 = center.latitude * math.pi / 180;
    final latitude2 = point.latitude * math.pi / 180;
    final latitudeDelta = latitude2 - latitude1;
    final longitudeDelta = (point.longitude - center.longitude) * math.pi / 180;
    final haversine =
        (math.pow(math.sin(latitudeDelta / 2), 2) +
                math.cos(latitude1) *
                    math.cos(latitude2) *
                    math.pow(math.sin(longitudeDelta / 2), 2))
            .clamp(0, 1)
            .toDouble();
    final angularDistance =
        2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
    return earthRadiusMeters * angularDistance <= radiusMeters;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'center': center.toJson(),
      'radiusMeters': radiusMeters,
      'strokeColor': strokeColor.toARGB32(),
      'fillColor': fillColor.toARGB32(),
      'strokeWidth': strokeWidth,
    };
  }
}

class AmapMapPin {
  const AmapMapPin({
    required this.position,
    this.title,
    this.snippet,
    this.draggable = false,
    this.label,
    // Neutral fallback; semantic colors belong to the caller.
    this.pinColor = const Color(0xFF9E9E9E),
    this.labelTextColor = Colors.white,
    this.labelBackgroundColor = const Color(0xE62D3748),
    this.labelTextScaleFactor = 1,
    this.child,
  }) : assert(labelTextScaleFactor > 0 && labelTextScaleFactor <= 4);

  final AmapLatLng position;
  final String? title;
  final String? snippet;
  final bool draggable;
  final String? label;
  final Color pinColor;
  final Color labelTextColor;
  final Color labelBackgroundColor;

  /// Controls the native label's font and container scale.
  ///
  /// The native implementations do not read the platform font scale. Callers
  /// that want scalable labels should pass the scale selected by Flutter.
  final double labelTextScaleFactor;
  final Widget? child;

  Map<String, Object?> toJson() => _toJson();

  Map<String, Object?> _toJson({
    AmapLatLng? position,
    Uint8List? imageBytes,
    double? imageWidth,
    double? imageHeight,
  }) {
    return <String, Object?>{
      'position': (position ?? this.position).toJson(),
      'title': title,
      'snippet': snippet,
      'draggable': draggable,
      'label': label,
      'pinColor': pinColor.toARGB32(),
      'labelTextColor': labelTextColor.toARGB32(),
      'labelBackgroundColor': labelBackgroundColor.toARGB32(),
      'labelTextScaleFactor': labelTextScaleFactor,
      'imageBytes': imageBytes,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
    };
  }
}

class AmapMapPolyline {
  const AmapMapPolyline({
    required this.points,
    this.color = const Color(0xFFFF5B00),
    this.width = 6,
    this.dashed = false,
    this.movingPin,
  });

  final List<AmapLatLng> points;
  final Color color;
  final double width;
  final bool dashed;

  /// Optional pin that follows the last point while the polyline is updated.
  ///
  /// [AmapMapPin.position] is used until [points] contains a coordinate.
  final AmapMapPin? movingPin;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'points': points.map((point) => point.toJson()).toList(growable: false),
      'color': color.toARGB32(),
      'width': width,
      'dashed': dashed,
    };
  }
}
