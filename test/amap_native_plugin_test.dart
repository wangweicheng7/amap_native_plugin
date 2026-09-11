import 'package:amap_native_plugin/amap_native_plugin.dart';
import 'package:amap_native_plugin/amap_native_plugin_method_channel.dart';
import 'package:amap_native_plugin/amap_native_plugin_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  Future<List<Map<Object?, Object?>>> searchPlaces(
    String keyword, {
    double? latitude,
    double? longitude,
  }) async {
    return <Map<Object?, Object?>>[
      <Object?, Object?>{
        'name': keyword,
        'latitude': 30.5728,
        'longitude': 104.0668,
        'district': '四川省成都市',
        'address': '',
      },
    ];
  }
}

void main() {
  final initialPlatform = AmapNativePluginPlatform.instance;

  test('$MethodChannelAmapNativePlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAmapNativePlugin>());
  });

  test('Android maps default to TextureMapView rendering', () {
    expect(const AmapMapView().useTextureView, isTrue);
  });

  test('init delegates to platform implementation', () async {
    final fakePlatform = MockAmapNativePluginPlatform();
    AmapNativePluginPlatform.instance = fakePlatform;

    await AmapNative.init(androidApiKey: 'android-key', iosApiKey: 'ios-key');

    expect(fakePlatform.initialized, isTrue);
  });

  test('searchPlaces maps platform data', () async {
    final fakePlatform = MockAmapNativePluginPlatform();
    AmapNativePluginPlatform.instance = fakePlatform;

    final places = await AmapNative.searchPlaces(
      '成都市',
      location: const AmapLatLng(30.5728, 104.0668),
    );

    expect(places.single.name, '成都市');
    expect(places.single.latitude, 30.5728);
    expect(places.single.longitude, 104.0668);
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

  test('circle geofence detects inside and outside coordinates', () {
    const geofence = AmapCircleGeofence(
      center: AmapLatLng(31.2304, 121.4737),
      radiusMeters: 500,
    );

    expect(geofence.contains(const AmapLatLng(31.2310, 121.4742)), isTrue);
    expect(geofence.contains(const AmapLatLng(31.2404, 121.4737)), isFalse);
  });

  test('map pin serializes placement parameters', () {
    const pin = AmapMapPin(
      position: AmapLatLng(31.2304, 121.4737),
      title: 'Shanghai',
      snippet: 'Center pin',
      draggable: true,
      label: 'Custom label',
      pinColor: Color(0xFF7C3AED),
      labelTextColor: Color(0xFFFFFFFF),
      labelBackgroundColor: Color(0xE67C3AED),
      labelTextScaleFactor: 1.5,
      child: SizedBox(width: 48, height: 48),
    );

    expect(pin.toJson(), <String, Object?>{
      'position': <String, Object?>{'latitude': 31.2304, 'longitude': 121.4737},
      'title': 'Shanghai',
      'snippet': 'Center pin',
      'draggable': true,
      'label': 'Custom label',
      'pinColor': 0xFF7C3AED,
      'labelTextColor': 0xFFFFFFFF,
      'labelBackgroundColor': 0xE67C3AED,
      'labelTextScaleFactor': 1.5,
      'imageBytes': null,
      'imageWidth': null,
      'imageHeight': null,
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

  test('polyline accepts a pin that follows its last point', () {
    const movingPin = AmapMapPin(
      position: AmapLatLng(39.909187, 116.397451),
      title: 'Moving position',
    );
    const polyline = AmapMapPolyline(
      points: [
        AmapLatLng(39.909187, 116.397451),
        AmapLatLng(39.9102, 116.3991),
      ],
      movingPin: movingPin,
    );

    expect(polyline.movingPin, same(movingPin));
    expect(
      () => const StandardMessageCodec().encodeMessage(polyline.toJson()),
      returnsNormally,
    );
  });

  test('map pin widget is not sent through the platform codec', () {
    const child = SizedBox(width: 48, height: 48);
    const pin = AmapMapPin(
      position: AmapLatLng(31.2304, 121.4737),
      child: child,
    );

    expect(pin.child, same(child));
    expect(pin.toJson(), isNot(contains('child')));
    expect(
      () => const StandardMessageCodec().encodeMessage(pin.toJson()),
      returnsNormally,
    );
  });

  testWidgets('map pin widget can be rendered for the native marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: AmapMapView(
            pins: <AmapMapPin>[
              AmapMapPin(
                position: AmapLatLng(31.2304, 121.4737),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: ColoredBox(color: Colors.orange),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('moving polyline pin can render a Flutter widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: AmapMapView(
            polylines: <AmapMapPolyline>[
              AmapMapPolyline(
                points: <AmapLatLng>[
                  AmapLatLng(31.2304, 121.4737),
                  AmapLatLng(31.2310, 121.4742),
                ],
                movingPin: AmapMapPin(
                  position: AmapLatLng(31.2304, 121.4737),
                  child: SizedBox(
                    key: ValueKey<String>('moving-track-pin'),
                    width: 48,
                    height: 48,
                    child: ColoredBox(color: Colors.green),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('moving-track-pin')), findsOne);
    expect(tester.takeException(), isNull);
  });
}
