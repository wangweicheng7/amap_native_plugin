import 'package:amap_native_plugin/amap_native_plugin.dart';
import 'package:amap_native_plugin/amap_native_plugin_method_channel.dart';
import 'package:amap_native_plugin/amap_native_plugin_platform_interface.dart';
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
}
