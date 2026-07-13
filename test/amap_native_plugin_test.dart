import 'package:amap_native_plugin/amap_native_plugin.dart';
import 'package:amap_native_plugin/amap_native_plugin_method_channel.dart';
import 'package:amap_native_plugin/amap_native_plugin_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAmapNativePluginPlatform
    with MockPlatformInterfaceMixin
    implements AmapNativePluginPlatform {
  bool initialized = false;

  @override
  Future<void> init({
    String? androidApiKey,
    String? iosApiKey,
    bool androidPrivacyShown = true,
    bool androidPrivacyAgreed = true,
  }) async {
    initialized = true;
  }
}

void main() {
  final initialPlatform = AmapNativePluginPlatform.instance;

  test('$MethodChannelAmapNativePlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAmapNativePlugin>());
  });

  test('init delegates to platform implementation', () async {
    final fakePlatform = MockAmapNativePluginPlatform();
    AmapNativePluginPlatform.instance = fakePlatform;

    await AmapNative.init(androidApiKey: 'android-key', iosApiKey: 'ios-key');

    expect(fakePlatform.initialized, isTrue);
  });

  test('circle geofence serializes drawing parameters', () {
    const geofence = AmapCircleGeofence(
      center: AmapLatLng(31.2304, 121.4737),
      radiusMeters: 1500,
    );

    expect(geofence.toJson(), <String, Object?>{
      'center': <String, Object?>{'latitude': 31.2304, 'longitude': 121.4737},
      'radiusMeters': 1500,
      'strokeColor': 0xFF2563EB,
      'fillColor': 0x332563EB,
      'strokeWidth': 2,
    });
  });

  test('map pin serializes placement parameters', () {
    const pin = AmapMapPin(
      position: AmapLatLng(31.2304, 121.4737),
      title: 'Shanghai',
      snippet: 'Center pin',
      draggable: true,
    );

    expect(pin.toJson(), <String, Object?>{
      'position': <String, Object?>{'latitude': 31.2304, 'longitude': 121.4737},
      'title': 'Shanghai',
      'snippet': 'Center pin',
      'draggable': true,
    });
  });

  test('polyline serializes coordinate and style parameters', () {
    const polyline = AmapMapPolyline(
      points: [
        AmapLatLng(39.909187, 116.397451),
        AmapLatLng(39.9102, 116.3991),
      ],
      color: Color(0xFFFF5B00),
      width: 6,
    );

    expect(polyline.toJson(), <String, Object?>{
      'points': <Map<String, Object?>>[
        <String, Object?>{'latitude': 39.909187, 'longitude': 116.397451},
        <String, Object?>{'latitude': 39.9102, 'longitude': 116.3991},
      ],
      'color': 0xFFFF5B00,
      'width': 6,
    });
  });
}
