import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'amap_native_plugin_platform_interface.dart';

part 'src/models/map_overlays.dart';
part 'src/map_controller.dart';
part 'src/map_view.dart';
part 'src/marker_renderer.dart';

/// Initializes the map SDK. Location collection and search are host concerns.
class AmapNative {
  AmapNative._();

  static Future<void> init({
    String? androidApiKey,
    String? iosApiKey,
    String? ohosApiKey,
    bool privacyShown = false,
    bool privacyAgreed = false,
    @Deprecated('Use privacyShown') bool? androidPrivacyShown,
    @Deprecated('Use privacyAgreed') bool? androidPrivacyAgreed,
  }) => AmapNativePluginPlatform.instance.init(
    androidApiKey: androidApiKey,
    iosApiKey: iosApiKey,
    ohosApiKey: ohosApiKey,
    privacyShown: androidPrivacyShown ?? privacyShown,
    privacyAgreed: androidPrivacyAgreed ?? privacyAgreed,
  );
}
