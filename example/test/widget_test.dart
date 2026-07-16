import 'package:amap_native_plugin/amap_native_plugin.dart';
import 'package:amap_native_plugin_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('random pin page draws three geofences and one pin', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    await tester.scrollUntilVisible(
      find.text('三围栏随机大头针判断'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('三围栏随机大头针判断'));
    await tester.pumpAndSettle();

    final map = tester.widget<AmapMapView>(find.byType(AmapMapView));
    expect(map.circleGeofences, hasLength(3));
    expect(map.pins, hasLength(1));
    expect(find.byKey(const ValueKey<String>('geofence-result')), findsOne);
    expect(find.textContaining('判断结果：'), findsOne);
  });
}
