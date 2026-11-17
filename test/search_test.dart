import 'package:amap_native_plugin/amap_native_plugin.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('amap_native_plugin');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'input tips preserve places without coordinates and request options',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return [
          {
            'id': 'poi',
            'name': '公园',
            'address': '路1号',
            'district': '城区',
            'adCode': '123',
            'latitude': 30.5,
            'longitude': 104.0,
          },
          {'name': '区域建议'},
        ];
      });
      final places = await AmapSearch.searchPlaces(
        keyword: ' 公园 ',
        location: const AmapLatLng(30.5, 104),
        city: '成都',
        cityLimit: true,
      );
      expect(places.first.position?.longitude, 104);
      expect(places.first.adCode, '123');
      expect(places.last.position, isNull);
      expect(() => places.clear(), throwsUnsupportedError);
      expect(calls.single.method, 'searchPlaces');
      expect(calls.single.arguments, containsPair('keyword', '公园'));
      expect(
        calls.single.arguments,
        containsPair('location', {'latitude': 30.5, 'longitude': 104.0}),
      );
      expect(calls.single.arguments, containsPair('cityLimit', true));
      expect(calls.single.arguments, containsPair('timeoutMs', 15000));
    },
  );

  test(
    'reverse geocoding uses GCJ02 coordinates and keeps empty city',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {
          'formattedAddress': '北京市',
          'province': '北京市',
          'city': '',
          'district': '东城区',
          'adCode': '110101',
        };
      });
      final value = await AmapSearch.reverseGeocode(
        position: const AmapLatLng(39.9, 116.4),
        radiusMeters: 300,
      );
      expect(value?.formattedAddress, '北京市');
      expect(value?.city, '');
      expect(calls.single.method, 'reverseGeocode');
      expect(calls.single.arguments, containsPair('radiusMeters', 300.0));
    },
  );

  test('empty native responses are normal empty results', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await AmapSearch.searchPlaces(keyword: '公园'), isEmpty);
    expect(
      await AmapSearch.reverseGeocode(position: const AmapLatLng(0, 0)),
      isNull,
    );
  });

  test(
    'concurrent searches receive unique IDs and independent results',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final keyword = (call.arguments as Map)['keyword'] as String;
        if (keyword == 'first') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        return [
          {'name': keyword},
        ];
      });
      final results = await Future.wait([
        AmapSearch.searchPlaces(keyword: 'first'),
        AmapSearch.searchPlaces(keyword: 'second'),
      ]);
      expect(results.first.single.name, 'first');
      expect(results.last.single.name, 'second');
      expect(
        calls.map((call) => (call.arguments as Map)['requestId']).toSet(),
        hasLength(2),
      );
    },
  );

  test('timeout cancels only its own native request', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'searchPlaces') {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return [];
      }
      return null;
    });
    await expectLater(
      AmapSearch.searchPlaces(
        keyword: '公园',
        timeout: const Duration(milliseconds: 5),
      ),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'timeout'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(calls.map((call) => call.method), ['searchPlaces', 'cancelSearch']);
    expect(
      (calls.last.arguments as Map)['requestId'],
      (calls.first.arguments as Map)['requestId'],
    );
  });

  test('native SDK errors retain their vendor code', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'auth_error',
        details: {'vendorCode': 1001},
      );
    });
    await expectLater(
      AmapSearch.searchPlaces(keyword: '公园'),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'auth_error')
            .having((e) => e.details, 'details', {'vendorCode': 1001}),
      ),
    );
  });

  test('invalid arguments never enter native SDK', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    for (final keyword in ['', ' ', 'x' * 81]) {
      await expectLater(
        AmapSearch.searchPlaces(keyword: keyword),
        throwsArgumentError,
      );
    }
    await expectLater(
      AmapSearch.searchPlaces(keyword: '公园', cityLimit: true),
      throwsArgumentError,
    );
    for (final point in [AmapLatLng(double.nan, 0), const AmapLatLng(0, 181)]) {
      await expectLater(
        AmapSearch.reverseGeocode(position: point),
        throwsArgumentError,
      );
      await expectLater(
        AmapSearch.searchPlaces(keyword: '公园', location: point),
        throwsArgumentError,
      );
    }
    for (final radius in [0.0, 3001.0, double.infinity]) {
      await expectLater(
        AmapSearch.reverseGeocode(
          position: const AmapLatLng(0, 0),
          radiusMeters: radius,
        ),
        throwsArgumentError,
      );
    }
    for (final timeout in [Duration.zero, const Duration(seconds: 61)]) {
      await expectLater(
        AmapSearch.searchPlaces(keyword: '公园', timeout: timeout),
        throwsArgumentError,
      );
    }
    expect(calls, isEmpty);
  });
}
