import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'amap_native_plugin_platform_interface.dart';

class MethodChannelAmapNativePlugin extends AmapNativePluginPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('amap_native_plugin');

  @override
  Future<void> init({
    String? androidApiKey,
    String? iosApiKey,
    String? ohosApiKey,
    bool privacyShown = false,
    bool privacyAgreed = false,
  }) => methodChannel.invokeMethod<void>('init', <String, Object?>{
    'androidApiKey': androidApiKey,
    'iosApiKey': iosApiKey,
    'ohosApiKey': ohosApiKey,
    'privacyShown': privacyShown,
    'privacyAgreed': privacyAgreed,
    'androidPrivacyShown': privacyShown,
    'androidPrivacyAgreed': privacyAgreed,
  });

  static int _nextRequest = 0;

  Future<T?> _search<T>(
    String method,
    Map<String, Object?> arguments,
    Duration timeout,
  ) {
    final requestId =
        'search_${DateTime.now().microsecondsSinceEpoch}_${_nextRequest++}';
    return methodChannel
        .invokeMethod<T>(method, {
          ...arguments,
          'requestId': requestId,
          'timeoutMs': timeout.inMilliseconds,
        })
        .timeout(
          timeout,
          onTimeout: () {
            unawaited(
              methodChannel
                  .invokeMethod<void>('cancelSearch', {'requestId': requestId})
                  .catchError((Object _) {}),
            );
            throw PlatformException(
              code: 'timeout',
              message: 'AMap search timed out.',
            );
          },
        );
  }

  @override
  Future<List<Object?>> searchPlaces({
    required String keyword,
    Map<String, Object?>? location,
    String? city,
    bool cityLimit = false,
    required Duration timeout,
  }) async =>
      await _search<List<Object?>>('searchPlaces', {
        'keyword': keyword,
        'location': location,
        'city': city,
        'cityLimit': cityLimit,
      }, timeout) ??
      const [];

  @override
  Future<Map<Object?, Object?>?> reverseGeocode({
    required Map<String, Object?> position,
    required double radiusMeters,
    required Duration timeout,
  }) => _search<Map<Object?, Object?>>('reverseGeocode', {
    'position': position,
    'radiusMeters': radiusMeters,
  }, timeout);
}
