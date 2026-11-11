import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'amap_native_plugin_method_channel.dart';

abstract class AmapNativePluginPlatform extends PlatformInterface {
  /// Constructs a AmapNativePluginPlatform.
  AmapNativePluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static AmapNativePluginPlatform _instance = MethodChannelAmapNativePlugin();

  /// The default instance of [AmapNativePluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelAmapNativePlugin].
  static AmapNativePluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AmapNativePluginPlatform] when
  /// they register themselves.
  static set instance(AmapNativePluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> init({
    String? androidApiKey,
    String? iosApiKey,
    String? ohosApiKey,
    bool privacyShown = false,
    bool privacyAgreed = false,
  }) => throw UnimplementedError('init() has not been implemented.');

  Widget buildMapView({
    required Map<String, Object?> creationParams,
    required PlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) => throw UnsupportedError(
    'No map view implementation registered for this platform.',
  );
}
