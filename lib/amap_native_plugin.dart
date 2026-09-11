import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'amap_native_plugin_platform_interface.dart';

class AmapNative {
  AmapNative._();

  static Future<void> init({
    String? androidApiKey,
    String? iosApiKey,
    bool androidPrivacyShown = true,
    bool androidPrivacyAgreed = true,
  }) {
    return AmapNativePluginPlatform.instance.init(
      androidApiKey: androidApiKey,
      iosApiKey: iosApiKey,
      androidPrivacyShown: androidPrivacyShown,
      androidPrivacyAgreed: androidPrivacyAgreed,
    );
  }

  static Future<List<AmapPlace>> searchPlaces(
    String keyword, {
    AmapLatLng? location,
  }) {
    return AmapNativePluginPlatform.instance
        .searchPlaces(
          keyword,
          latitude: location?.latitude,
          longitude: location?.longitude,
        )
        .then(
          (places) => places.map(AmapPlace.fromJson).toList(growable: false),
        );
  }

  /// Android 上模拟器可能会在创建高德地图原生视图时触发 EGL 崩溃。
  /// 探测失败时保守返回 true，沿用原生渲染路径。
  static Future<bool> shouldUseNativeMap() async {
    try {
      final result = await const MethodChannel('amap_native_plugin')
          .invokeMethod<bool>('shouldUseNativeMap');
      return result == true;
    } catch (_) {
      return true;
    }
  }
}

class AmapPlace {
  const AmapPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.district,
    required this.address,
  });

  factory AmapPlace.fromJson(Map<Object?, Object?> json) {
    return AmapPlace(
      name: json['name']?.toString() ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      district: json['district']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
    );
  }

  final String name;
  final double latitude;
  final double longitude;
  final String district;
  final String address;
}

class AmapLatLng {
  const AmapLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() {
    return <String, Object?>{'latitude': latitude, 'longitude': longitude};
  }
}

class AmapCircleGeofence {
  const AmapCircleGeofence({
    required this.center,
    required this.radiusMeters,
    this.strokeColor = const Color(0xFF2563EB),
    this.fillColor = const Color(0x332563EB),
    this.strokeWidth = 2,
  });

  final AmapLatLng center;
  final double radiusMeters;
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  /// Returns whether [point] is inside or on this circular geofence.
  bool contains(AmapLatLng point) {
    const earthRadiusMeters = 6378137.0;
    final latitude1 = center.latitude * math.pi / 180;
    final latitude2 = point.latitude * math.pi / 180;
    final latitudeDelta = latitude2 - latitude1;
    final longitudeDelta = (point.longitude - center.longitude) * math.pi / 180;
    final haversine =
        (math.pow(math.sin(latitudeDelta / 2), 2) +
                math.cos(latitude1) *
                    math.cos(latitude2) *
                    math.pow(math.sin(longitudeDelta / 2), 2))
            .clamp(0, 1)
            .toDouble();
    final angularDistance =
        2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
    return earthRadiusMeters * angularDistance <= radiusMeters;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'center': center.toJson(),
      'radiusMeters': radiusMeters,
      'strokeColor': strokeColor.toARGB32(),
      'fillColor': fillColor.toARGB32(),
      'strokeWidth': strokeWidth,
    };
  }
}

class AmapMapPin {
  const AmapMapPin({
    required this.position,
    this.title,
    this.snippet,
    this.draggable = false,
    this.label,
    // 中性灰：降级兜底针不得落在「状态色板」里。宿主应用用针色编码安全状态
    // （绿=安全 / 琥珀=警告 / 红=离开安全区），原先的橙 #F97316 夹在警告与危险之间，
    // 会把「位图没画出来」误读成「宠物出事了」。
    this.pinColor = const Color(0xFF9E9E9E),
    this.labelTextColor = Colors.white,
    this.labelBackgroundColor = const Color(0xE62D3748),
    this.labelTextScaleFactor = 1,
    this.child,
  }) : assert(labelTextScaleFactor > 0 && labelTextScaleFactor <= 4);

  final AmapLatLng position;
  final String? title;
  final String? snippet;
  final bool draggable;
  final String? label;
  final Color pinColor;
  final Color labelTextColor;
  final Color labelBackgroundColor;

  /// Controls the native label's font and container scale.
  ///
  /// The native implementations do not read the platform font scale. Callers
  /// that want scalable labels should pass the scale selected by Flutter.
  final double labelTextScaleFactor;
  final Widget? child;

  Map<String, Object?> toJson() => _toJson();

  Map<String, Object?> _toJson({
    AmapLatLng? position,
    Uint8List? imageBytes,
    double? imageWidth,
    double? imageHeight,
  }) {
    return <String, Object?>{
      'position': (position ?? this.position).toJson(),
      'title': title,
      'snippet': snippet,
      'draggable': draggable,
      'label': label,
      'pinColor': pinColor.toARGB32(),
      'labelTextColor': labelTextColor.toARGB32(),
      'labelBackgroundColor': labelBackgroundColor.toARGB32(),
      'labelTextScaleFactor': labelTextScaleFactor,
      'imageBytes': imageBytes,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
    };
  }
}

class AmapMapPolyline {
  const AmapMapPolyline({
    required this.points,
    this.color = const Color(0xFFFF5B00),
    this.width = 6,
    this.movingPin,
  });

  final List<AmapLatLng> points;
  final Color color;
  final double width;

  /// Optional pin that follows the last point while the polyline is updated.
  ///
  /// [AmapMapPin.position] is used until [points] contains a coordinate.
  final AmapMapPin? movingPin;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'points': points.map((point) => point.toJson()).toList(growable: false),
      'color': color.toARGB32(),
      'width': width,
    };
  }
}

typedef AmapCameraChangedCallback = void Function(AmapLatLng center);
typedef AmapMapTapCallback = void Function(AmapLatLng position);

class AmapMapController {
  AmapMapController(int mapId)
    : _channel = MethodChannel('amap_native_plugin/map_view_$mapId');

  final MethodChannel _channel;

  Future<void> moveCamera({required AmapLatLng center, required double zoom}) {
    return _channel.invokeMethod<void>('moveCamera', <String, Object?>{
      'center': center.toJson(),
      'zoom': zoom,
    });
  }

  Future<void> fitAllOverlays({double padding = 48}) {
    return _channel.invokeMethod<void>('fitAllOverlays', <String, Object?>{
      'padding': padding,
    });
  }

  Future<void> zoomBy(double amount) {
    return _channel.invokeMethod<void>('zoomBy', <String, Object?>{
      'amount': amount,
    });
  }

  /// 截取当前地图视图的截图（原生高德 SDK 渲染内容，包括瓦片和所有覆盖物）。
  /// 返回 PNG 格式的字节数据，失败时返回 null。
  Future<Uint8List?> takeSnapshot() {
    return _channel.invokeMethod<Uint8List>('takeSnapshot');
  }
}

class AmapMapView extends StatefulWidget {
  const AmapMapView({
    super.key,
    this.width,
    this.height,
    this.initialCenter,
    this.initialZoom,
    this.circleGeofences = const <AmapCircleGeofence>[],
    this.pins = const <AmapMapPin>[],
    this.polylines = const <AmapMapPolyline>[],
    this.showMyLocation = false,
    this.visible = true,
    this.useTextureView = true,
    this.zoomControlsEnabled = true,
    this.centerPin,
    this.movingCenterPin,
    this.onCameraMove,
    this.onCameraIdle,
    this.onMapTap,
    this.gestureRecognizers,
    this.onMapCreated,
  });

  final double? width;
  final double? height;
  final AmapLatLng? initialCenter;
  final double? initialZoom;
  final List<AmapCircleGeofence> circleGeofences;
  final List<AmapMapPin> pins;
  final List<AmapMapPolyline> polylines;
  final bool showMyLocation;
  final bool visible;

  /// Android 默认使用高德 TextureMapView，避免业务页面意外退回 GLSurfaceView。
  final bool useTextureView;

  /// Android 是否显示高德原生放大/缩小控件。
  final bool zoomControlsEnabled;
  final Widget? centerPin;
  final Widget? movingCenterPin;
  final AmapCameraChangedCallback? onCameraMove;
  final AmapCameraChangedCallback? onCameraIdle;
  final AmapMapTapCallback? onMapTap;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;
  final PlatformViewCreatedCallback? onMapCreated;

  static const String _viewType = 'amap_native_plugin/map_view';

  @override
  State<AmapMapView> createState() => _AmapMapViewState();
}

class _AmapMapViewState extends State<AmapMapView> {
  MethodChannel? _viewChannel;
  bool _isCameraMoving = false;
  late List<GlobalKey> _pinRenderKeys;
  late List<_RenderedPin?> _renderedPins;
  int _pinRenderGeneration = 0;

  Map<String, Object?> get _creationParams {
    return <String, Object?>{
      'initialCenter': widget.initialCenter?.toJson(),
      'initialZoom': widget.initialZoom,
      'circleGeofences': _circleGeofencesJson,
      'pins': _pinsJson,
      'polylines': _polylinesJson,
      'showMyLocation': widget.showMyLocation,
      'visible': widget.visible,
      'useTextureView': widget.useTextureView,
      'zoomControlsEnabled': widget.zoomControlsEnabled,
    };
  }

  List<Map<String, Object?>> get _circleGeofencesJson {
    return widget.circleGeofences
        .map((geofence) => geofence.toJson())
        .toList(growable: false);
  }

  List<Map<String, Object?>> get _pinsJson {
    final definitions = _pinDefinitions(widget);
    return List<Map<String, Object?>>.generate(definitions.length, (index) {
      final renderedPin = _renderedPins[index];
      return definitions[index]._toJson(
        position: _pinPosition(widget, index),
        imageBytes: renderedPin?.bytes,
        imageWidth: renderedPin?.width,
        imageHeight: renderedPin?.height,
      );
    }, growable: false);
  }

  List<Map<String, Object?>> get _polylinesJson {
    return widget.polylines
        .map((polyline) => polyline.toJson())
        .toList(growable: false);
  }

  List<Map<String, Object?>> get _movingPinUpdatesJson {
    return List<Map<String, Object?>>.generate(widget.polylines.length, (
      index,
    ) {
      final polyline = widget.polylines[index];
      final pin = polyline.movingPin;
      if (pin == null) {
        return const <String, Object?>{};
      }
      return <String, Object?>{
        'index': widget.pins.length + _movingPinOffset(index),
        'position': (polyline.points.lastOrNull ?? pin.position).toJson(),
      };
    }, growable: false).where((update) => update.isNotEmpty).toList();
  }

  @override
  void initState() {
    super.initState();
    _resetPinRenderState();
    _schedulePinRendering();
  }

  @override
  void didUpdateWidget(covariant AmapMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pinDefinitionsChanged = !listEquals(
      _pinDefinitions(oldWidget),
      _pinDefinitions(widget),
    );
    if (!listEquals(oldWidget.circleGeofences, widget.circleGeofences)) {
      _viewChannel?.invokeMethod<void>(
        'updateCircleGeofences',
        <String, Object?>{'circleGeofences': _circleGeofencesJson},
      ).catchError((Object _) {});
    }

    if (pinDefinitionsChanged) {
      _resetPinRenderState();
      _schedulePinRendering();
    }

    if (!listEquals(oldWidget.polylines, widget.polylines)) {
      _viewChannel?.invokeMethod<void>('updatePolylines', <String, Object?>{
        'polylines': _polylinesJson,
      }).catchError((Object _) {});
      if (!pinDefinitionsChanged && _movingPinUpdatesJson.isNotEmpty) {
        _viewChannel?.invokeMethod<void>('updateMovingPins', <String, Object?>{
          'updates': _movingPinUpdatesJson,
        }).catchError((Object _) {});
      }
    }

    // creationParams 只在原生视图创建的那一刻被读一次,之后 Flutter 侧再改
    // showMyLocation 原生是收不到的 —— 调用方「首帧用原生蓝点兜底、拿到定位后
    // 切自绘针」的意图会只生效一半:蓝点开了就永远关不掉,与自绘针并存。
    if (oldWidget.visible != widget.visible && widget.visible) {
      _updateNativeVisibility();
    }
    if (oldWidget.showMyLocation != widget.showMyLocation) {
      _viewChannel?.invokeMethod<void>('updateMyLocation', <String, Object?>{
        'showMyLocation': widget.showMyLocation,
      }).catchError((Object _) {});
    }
    if (oldWidget.visible != widget.visible && !widget.visible) {
      _updateNativeVisibility();
    }
  }

  @override
  void dispose() {
    _viewChannel?.setMethodCallHandler(null);
    // Android 的 PlatformViewsController 会先把原生 View 从树中摘除，再调用
    // PlatformView.dispose。不要从 Dart 提前销毁 TextureMapView：否则后续 detach
    // 会进入高德 GLTextureView 的同步等待，部分真机会直接 ANR。
    _viewChannel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget view;
    // 用 defaultTargetPlatform 而非 dart:io 的 Platform.isAndroid：后者在 widget
    // 测试里恒为宿主机（Linux/macOS），平台视图分支永远走不到，于是「widget 变化
    // → 方法通道下发」这类接线根本无法被测试覆盖 —— showMyLocation 关不掉正是
    // 藏在这个测不到的分支后面。本仓 geolocator_phone_location_service 早已按同
    // 一理由选择 defaultTargetPlatform。
    if (defaultTargetPlatform == TargetPlatform.android) {
      view = AndroidView(
        viewType: AmapMapView._viewType,
        creationParams: _creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: widget.gestureRecognizers,
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      view = UiKitView(
        viewType: AmapMapView._viewType,
        creationParams: _creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: widget.gestureRecognizers,
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else {
      view = const ColoredBox(
        color: Color(0xFFE5E7EB),
        child: Center(
          child: Text('AMap is only supported on Android and iOS.'),
        ),
      );
    }

    final retainedView = IgnorePointer(
      ignoring: !widget.visible,
      child: Opacity(
        opacity: widget.visible ? 1 : 0,
        child: _withPinRenderers(_withCenterPin(view)),
      ),
    );
    if (widget.width == null && widget.height == null) {
      return retainedView;
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: retainedView,
    );
  }

  void _onPlatformViewCreated(int id) {
    _viewChannel = MethodChannel('amap_native_plugin/map_view_$id');
    _viewChannel?.setMethodCallHandler(_handlePlatformViewCall);
    _viewChannel?.invokeMethod<void>('updateCircleGeofences', <String, Object?>{
      'circleGeofences': _circleGeofencesJson,
    }).catchError((Object _) {});
    _viewChannel?.invokeMethod<void>('updatePins', <String, Object?>{
      'pins': _pinsJson,
    }).catchError((Object _) {});
    _schedulePinRendering();
    _viewChannel?.invokeMethod<void>('updatePolylines', <String, Object?>{
      'polylines': _polylinesJson,
    }).catchError((Object _) {});
    // 与其它图层一致地重推一次:creationParams 是首帧快照,视图创建完成前 widget
    // 可能已经重建过(定位回调常在此窗口内到达)。
    _viewChannel?.invokeMethod<void>('updateMyLocation', <String, Object?>{
      'showMyLocation': widget.showMyLocation,
    }).catchError((Object _) {});
    _updateNativeVisibility();
    widget.onMapCreated?.call(id);
  }

  void _updateNativeVisibility() {
    _viewChannel?.invokeMethod<void>('setVisible', <String, Object?>{
      'visible': widget.visible,
    }).catchError((Object _) {});
  }

  Future<void> _handlePlatformViewCall(MethodCall call) async {
    switch (call.method) {
      case 'cameraMove':
        final center = _latLngFromArguments(call.arguments);
        if (center == null) {
          return;
        }
        if (!_isCameraMoving) {
          setState(() {
            _isCameraMoving = true;
          });
        }
        widget.onCameraMove?.call(center);
        break;
      case 'cameraIdle':
        final center = _latLngFromArguments(call.arguments);
        if (center == null) {
          return;
        }
        setState(() {
          _isCameraMoving = false;
        });
        widget.onCameraIdle?.call(center);
        break;
      case 'mapTap':
        final position = _latLngFromArguments(call.arguments);
        if (position == null) {
          return;
        }
        widget.onMapTap?.call(position);
        break;
    }
  }

  AmapLatLng? _latLngFromArguments(Object? arguments) {
    final args = arguments as Map<Object?, Object?>?;
    final latitude = args?['latitude'];
    final longitude = args?['longitude'];
    if (latitude is! num || longitude is! num) {
      return null;
    }

    return AmapLatLng(latitude.toDouble(), longitude.toDouble());
  }

  Widget _withCenterPin(Widget mapView) {
    final pin = _isCameraMoving
        ? widget.movingCenterPin ?? widget.centerPin
        : widget.centerPin;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: mapView),
        if (pin != null) IgnorePointer(child: Center(child: pin)),
      ],
    );
  }

  Widget _withPinRenderers(Widget mapView) {
    final renderers = <Widget>[];
    final definitions = _pinDefinitions(widget);
    for (var index = 0; index < definitions.length; index++) {
      final child = definitions[index].child;
      if (child == null) {
        continue;
      }
      renderers.add(
        Positioned(
          top: 0,
          left: 0,
          child: RepaintBoundary(key: _pinRenderKeys[index], child: child),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ...renderers,
        Positioned.fill(
          key: const ValueKey('amap-native-view-slot'),
          child: mapView,
        ),
      ],
    );
  }

  void _resetPinRenderState() {
    _pinRenderGeneration++;
    _pinRenderKeys = List<GlobalKey>.generate(
      _pinDefinitions(widget).length,
      (_) => GlobalKey(),
      growable: false,
    );
    _renderedPins = List<_RenderedPin?>.filled(
      _pinDefinitions(widget).length,
      null,
    );
  }

  void _schedulePinRendering() {
    final generation = _pinRenderGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_renderPins(generation));
    });
  }

  Future<void> _renderPins(int generation) async {
    if (!mounted || generation != _pinRenderGeneration) {
      return;
    }
    final pins = _pinDefinitions(widget);
    final renderKeys = _pinRenderKeys;
    final renderedPins = List<_RenderedPin?>.filled(pins.length, null);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    for (var index = 0; index < pins.length; index++) {
      if (pins[index].child == null) {
        continue;
      }
      final renderObject = renderKeys[index].currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        _schedulePinRendering();
        return;
      }
      // `debugNeedsPaint` 只有 debug 构建可读 —— 它的实现是 `late bool` + assert，
      // release/profile 下 assert 被剥离，读取即抛 LateInitializationError。而本方法
      // 由 `unawaited(_renderPins(...))` 调起，异常被静默吞掉，`_renderedPins` 永不赋值，
      // 结果是所有带 child 的针都拿不到位图、退化成默认针。
      // release 视为「已绘制」是安全的：_renderPins 本就跑在 post-frame 回调里。
      var needsPaint = false;
      assert(() {
        needsPaint = renderObject.debugNeedsPaint;
        return true;
      }());
      if (needsPaint) {
        _schedulePinRendering();
        return;
      }
      final logicalSize = renderObject.size;
      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          continue;
        }
        renderedPins[index] = _RenderedPin(
          byteData.buffer.asUint8List(),
          logicalSize.width,
          logicalSize.height,
        );
      } finally {
        image.dispose();
      }
      if (!mounted || generation != _pinRenderGeneration) {
        return;
      }
    }

    if (!mounted || generation != _pinRenderGeneration) {
      return;
    }
    _renderedPins = renderedPins;
    try {
      await _viewChannel?.invokeMethod<void>('updatePins', <String, Object?>{
        'pins': _pinsJson,
      });
    } catch (_) {
      // 视图销毁竞态：dispose 后 channel 已失效，放弃本次针位图补发。
    }
  }

  List<AmapMapPin> _pinDefinitions(AmapMapView mapView) {
    return <AmapMapPin>[
      ...mapView.pins,
      for (final polyline in mapView.polylines) ?polyline.movingPin,
    ];
  }

  AmapLatLng _pinPosition(AmapMapView mapView, int definitionIndex) {
    if (definitionIndex < mapView.pins.length) {
      return mapView.pins[definitionIndex].position;
    }
    var movingPinIndex = definitionIndex - mapView.pins.length;
    for (final polyline in mapView.polylines) {
      final pin = polyline.movingPin;
      if (pin == null) {
        continue;
      }
      if (movingPinIndex == 0) {
        return polyline.points.lastOrNull ?? pin.position;
      }
      movingPinIndex--;
    }
    throw RangeError.index(definitionIndex, _pinDefinitions(mapView));
  }

  int _movingPinOffset(int polylineIndex) {
    var offset = 0;
    for (var index = 0; index < polylineIndex; index++) {
      if (widget.polylines[index].movingPin != null) {
        offset++;
      }
    }
    return offset;
  }
}

class _RenderedPin {
  const _RenderedPin(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final double width;
  final double height;
}
