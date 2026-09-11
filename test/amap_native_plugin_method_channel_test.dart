import 'package:amap_native_plugin/amap_native_plugin.dart';
import 'package:amap_native_plugin/amap_native_plugin_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelAmapNativePlugin();
  const channel = MethodChannel('amap_native_plugin');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
          calls.add(methodCall);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('init sends api keys and privacy flags', () async {
    await platform.init(
      androidApiKey: 'android-key',
      iosApiKey: 'ios-key',
      androidPrivacyShown: false,
      androidPrivacyAgreed: true,
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'init');
    expect(calls.single.arguments, <String, Object?>{
      'androidApiKey': 'android-key',
      'iosApiKey': 'ios-key',
      'androidPrivacyShown': false,
      'androidPrivacyAgreed': true,
    });
  });

  test('searchPlaces maps native results', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
          calls.add(methodCall);
          return <Map<String, Object?>>[
            <String, Object?>{
              'name': '成都市',
              'latitude': 30.5728,
              'longitude': 104.0668,
              'district': '四川省成都市',
              'address': '',
            },
          ];
        });

    final places = await platform.searchPlaces(
      '成都市',
      latitude: 30.5728,
      longitude: 104.0668,
    );

    expect(calls.single.method, 'searchPlaces');
    expect(calls.single.arguments, <String, Object?>{
      'keyword': '成都市',
      'latitude': 30.5728,
      'longitude': 104.0668,
    });
    expect(places.single['name'], '成都市');
  });

  test('pins update is forwarded to the platform view channel', () async {
    const viewChannel = MethodChannel('amap_native_plugin/map_view_1');
    final viewCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(viewChannel, (methodCall) async {
          viewCalls.add(methodCall);
          return null;
        });

    await viewChannel.invokeMethod<void>('updatePins', <String, Object?>{
      'pins': const [
        <String, Object?>{
          'position': <String, Object?>{
            'latitude': 31.2304,
            'longitude': 121.4737,
          },
          'title': 'Shanghai',
          'snippet': 'Center pin',
          'draggable': true,
          'label': null,
          'pinColor': 0xFF9E9E9E,
          'labelTextColor': 0xFFFFFFFF,
          'labelBackgroundColor': 0xE62D3748,
          'imageBytes': null,
          'imageWidth': null,
          'imageHeight': null,
        },
      ],
    });

    expect(viewCalls, hasLength(1));
    expect(viewCalls.single.method, 'updatePins');
    expect(viewCalls.single.arguments, isA<Map>());
    expect(
      viewCalls.single.arguments,
      containsPair('pins', const [
        <String, Object?>{
          'position': <String, Object?>{
            'latitude': 31.2304,
            'longitude': 121.4737,
          },
          'title': 'Shanghai',
          'snippet': 'Center pin',
          'draggable': true,
          'label': null,
          'pinColor': 0xFF9E9E9E,
          'labelTextColor': 0xFFFFFFFF,
          'labelBackgroundColor': 0xE62D3748,
          'imageBytes': null,
          'imageWidth': null,
          'imageHeight': null,
        },
      ]),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(viewChannel, null);
  });

  test('map controller forwards camera commands', () async {
    const viewChannel = MethodChannel('amap_native_plugin/map_view_7');
    final viewCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(viewChannel, (methodCall) async {
          viewCalls.add(methodCall);
          return null;
        });

    final controller = AmapMapController(7);
    await controller.moveCamera(
      center: const AmapLatLng(30.2747, 120.1558),
      zoom: 15,
    );
    await controller.fitAllOverlays(padding: 56);

    expect(viewCalls.map((call) => call.method), <String>[
      'moveCamera',
      'fitAllOverlays',
    ]);
    expect(viewCalls.first.arguments, <String, Object?>{
      'center': <String, Object?>{'latitude': 30.2747, 'longitude': 120.1558},
      'zoom': 15.0,
    });
    expect(viewCalls.last.arguments, <String, Object?>{'padding': 56.0});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(viewChannel, null);
  });

  test(
    'moving pin updates are forwarded to the platform view channel',
    () async {
      const viewChannel = MethodChannel('amap_native_plugin/map_view_9');
      final viewCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(viewChannel, (methodCall) async {
            viewCalls.add(methodCall);
            return null;
          });

      await viewChannel.invokeMethod<void>(
        'updateMovingPins',
        <String, Object?>{
          'updates': const <Map<String, Object?>>[
            <String, Object?>{
              'index': 1,
              'position': <String, Object?>{
                'latitude': 31.231,
                'longitude': 121.4742,
              },
            },
          ],
        },
      );

      expect(viewCalls.single.method, 'updateMovingPins');
      expect(viewCalls.single.arguments, containsPair('updates', isNotEmpty));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(viewChannel, null);
    },
  );
}
