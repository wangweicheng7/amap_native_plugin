part of '../amap_native_plugin.dart';

/// AMap native search services. All coordinates use GCJ-02.
abstract final class AmapSearch {
  static Future<List<AmapPlace>> searchPlaces({
    required String keyword,
    AmapLatLng? location,
    String? city,
    bool cityLimit = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError.value(keyword, 'keyword', 'Use 1 to 80 characters.');
    }
    if (cityLimit && (city == null || city.trim().isEmpty)) {
      throw ArgumentError('city is required when cityLimit is true.');
    }
    if (location != null) _validatePosition(location);
    _validateTimeout(timeout);
    final values = await AmapNativePluginPlatform.instance.searchPlaces(
      keyword: trimmed,
      location: location?.toJson(),
      city: city?.trim(),
      cityLimit: cityLimit,
      timeout: timeout,
    );
    return List.unmodifiable(
      values.map((value) {
        final data = Map<String, Object?>.from(value as Map);
        final latitude = (data['latitude'] as num?)?.toDouble();
        final longitude = (data['longitude'] as num?)?.toDouble();
        return AmapPlace(
          id: data['id'] as String? ?? '',
          name: data['name'] as String? ?? '',
          address: data['address'] as String? ?? '',
          district: data['district'] as String? ?? '',
          adCode: data['adCode'] as String? ?? '',
          position: latitude == null || longitude == null
              ? null
              : AmapLatLng(latitude, longitude),
        );
      }),
    );
  }

  static Future<AmapAddress?> reverseGeocode({
    required AmapLatLng position,
    double radiusMeters = 200,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _validatePosition(position);
    _validateTimeout(timeout);
    if (!radiusMeters.isFinite || radiusMeters < 1 || radiusMeters > 3000) {
      throw ArgumentError.value(
        radiusMeters,
        'radiusMeters',
        'Use 1 to 3000 meters.',
      );
    }
    final data = await AmapNativePluginPlatform.instance.reverseGeocode(
      position: position.toJson(),
      radiusMeters: radiusMeters,
      timeout: timeout,
    );
    if (data == null) return null;
    return AmapAddress(
      formattedAddress: data['formattedAddress'] as String? ?? '',
      province: data['province'] as String? ?? '',
      city: data['city'] as String? ?? '',
      district: data['district'] as String? ?? '',
      adCode: data['adCode'] as String? ?? '',
    );
  }

  static void _validatePosition(AmapLatLng position) {
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude.abs() > 90 ||
        position.longitude.abs() > 180) {
      throw ArgumentError.value(
        position,
        'position',
        'Invalid GCJ-02 coordinate.',
      );
    }
  }

  static void _validateTimeout(Duration timeout) {
    if (timeout.inMilliseconds < 1 || timeout > const Duration(seconds: 60)) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Use 1 to 60000 milliseconds.',
      );
    }
  }
}

/// Input tips may describe an area without a selectable coordinate.
@immutable
class AmapPlace {
  const AmapPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.district,
    required this.adCode,
    this.position,
  });

  final String id;
  final String name;
  final String address;
  final String district;
  final String adCode;
  final AmapLatLng? position;
}

@immutable
class AmapAddress {
  const AmapAddress({
    required this.formattedAddress,
    required this.province,
    required this.city,
    required this.district,
    required this.adCode,
  });

  final String formattedAddress;
  final String province;
  final String city;
  final String district;
  final String adCode;
}
