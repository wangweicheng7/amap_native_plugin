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
}
