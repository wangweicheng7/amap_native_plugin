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
}
