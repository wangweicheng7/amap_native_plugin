import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'amap_native_plugin_platform_interface.dart';

/// An implementation of [AmapNativePluginPlatform] that uses method channels.
class MethodChannelAmapNativePlugin extends AmapNativePluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('amap_native_plugin');

  @override
  Future<void> init({
    String? androidApiKey,
    String? iosApiKey,
    bool androidPrivacyShown = true,
    bool androidPrivacyAgreed = true,
  }) async {
    await methodChannel.invokeMethod<void>('init', <String, Object?>{
      'androidApiKey': androidApiKey,
      'iosApiKey': iosApiKey,
      'androidPrivacyShown': androidPrivacyShown,
      'androidPrivacyAgreed': androidPrivacyAgreed,
    });
  }

  @override
  Future<List<Map<Object?, Object?>>> searchPlaces(
    String keyword, {
    double? latitude,
    double? longitude,
  }) async {
    final results = await methodChannel.invokeListMethod<Object?>(
      'searchPlaces',
      <String, Object?>{
        'keyword': keyword,
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return (results ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .toList(growable: false);
  }
}
