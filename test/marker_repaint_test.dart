import 'package:amap_native_plugin/amap_native_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final images = <Uint8List>[];
  final channels = <MethodChannel>[];
  var created = 0;

  setUp(() {
    created = 0;
    images.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') {
          created++;
          final args = call.arguments as Map;
          final channel = MethodChannel(
            'amap_native_plugin/map_view_${args['id']}',
          );
          channels.add(channel);
          binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
            call,
          ) async {
            if (call.method == 'updatePins') {
              final args = call.arguments as Map;
              for (final pin in args['pins'] as List) {
                if (pin['imageBytes'] is Uint8List) {
                  images.add(pin['imageBytes']);
                }
              }
            }
            return null;
          });
          return 42;
        }
        return null;
      },
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      null,
    );
    for (final channel in channels) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
    channels.clear();
  });

  Future<void> flushImages(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
    }
  }

  testWidgets(
    'asynchronous marker repaint refreshes PNG without recreating the map',
    (tester) async {
      final color = ValueNotifier<Color>(Colors.red);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 200,
            height: 200,
            child: AmapMapView(
              pins: [
                AmapMapPin(
                  position: const AmapLatLng(31, 121),
                  child: ValueListenableBuilder<Color>(
                    valueListenable: color,
                    builder: (_, value, _) => SizedBox(
                      width: 24,
                      height: 24,
                      child: ColoredBox(color: value),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await flushImages(tester);
      expect(images, isNotEmpty);
      final initial = images.last;
      images.clear();
      color.value = Colors.blue;
      await flushImages(tester);
      expect(images, isNotEmpty);
      expect(listEquals(initial, images.last), isFalse);
      expect(created, 1);
      await tester.pumpWidget(const SizedBox());
      await flushImages(tester);
      color.dispose();
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );
}
