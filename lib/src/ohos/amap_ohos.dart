import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../amap_native_plugin_method_channel.dart';
import '../../amap_native_plugin_platform_interface.dart';

/// Loaded by the HarmonyOS Dart registrant, never by the Android/iOS entrypoint.
class AmapOhosPlugin extends MethodChannelAmapNativePlugin {
  static void registerWith() {
    AmapNativePluginPlatform.instance = AmapOhosPlugin();
  }

  @override
  Widget buildMapView({
    required Map<String, Object?> creationParams,
    required PlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) => OhosView(
    viewType: 'amap_native_plugin/map_view',
    creationParams: creationParams,
    creationParamsCodec: const StandardMessageCodec(),
    gestureRecognizers: gestureRecognizers,
    onPlatformViewCreated: onPlatformViewCreated,
  );
}
