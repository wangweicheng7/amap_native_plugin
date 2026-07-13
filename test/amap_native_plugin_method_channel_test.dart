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
        },
      ]),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(viewChannel, null);
  });
}
