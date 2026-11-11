part of '../amap_native_plugin.dart';

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

  /// Selects the native Android view type when the map is created.
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
  bool _pinRenderScheduled = false;
  bool _pinRenderingActive = false;
  bool _pinRenderDirty = false;

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
      _viewChannel
          ?.invokeMethod<void>('updateCircleGeofences', <String, Object?>{
            'circleGeofences': _circleGeofencesJson,
          })
          .catchError((Object _) {});
    }

    if (pinDefinitionsChanged) {
      _resetPinRenderState();
      _schedulePinRendering();
    }

    if (!listEquals(oldWidget.polylines, widget.polylines)) {
      _viewChannel
          ?.invokeMethod<void>('updatePolylines', <String, Object?>{
            'polylines': _polylinesJson,
          })
          .catchError((Object _) {});
      if (!pinDefinitionsChanged && _movingPinUpdatesJson.isNotEmpty) {
        _viewChannel
            ?.invokeMethod<void>('updateMovingPins', <String, Object?>{
              'updates': _movingPinUpdatesJson,
            })
            .catchError((Object _) {});
      }
    }

    // creationParams 只在原生视图创建的那一刻被读一次,之后 Flutter 侧再改
    // showMyLocation 原生是收不到的 —— 调用方「首帧用原生蓝点兜底、拿到定位后
    // 切自绘针」的意图会只生效一半:蓝点开了就永远关不掉,与自绘针并存。
    if (oldWidget.visible != widget.visible && widget.visible) {
      _updateNativeVisibility();
    }
    if (oldWidget.showMyLocation != widget.showMyLocation) {
      _viewChannel
          ?.invokeMethod<void>('updateMyLocation', <String, Object?>{
            'showMyLocation': widget.showMyLocation,
          })
          .catchError((Object _) {});
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
    } else if (defaultTargetPlatform.name == 'ohos') {
      view = AmapNativePluginPlatform.instance.buildMapView(
        creationParams: _creationParams,
        gestureRecognizers: widget.gestureRecognizers,
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else {
      view = const ColoredBox(
        color: Color(0xFFE5E7EB),
        child: Center(child: Text('AMap supports Android, iOS and HarmonyOS.')),
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
    if (!mounted) return;
    _viewChannel = MethodChannel('amap_native_plugin/map_view_$id');
    _viewChannel?.setMethodCallHandler(_handlePlatformViewCall);
    _viewChannel
        ?.invokeMethod<void>('updateCircleGeofences', <String, Object?>{
          'circleGeofences': _circleGeofencesJson,
        })
        .catchError((Object _) {});
    _viewChannel
        ?.invokeMethod<void>('updatePins', <String, Object?>{'pins': _pinsJson})
        .catchError((Object _) {});
    _schedulePinRendering();
    _viewChannel
        ?.invokeMethod<void>('updatePolylines', <String, Object?>{
          'polylines': _polylinesJson,
        })
        .catchError((Object _) {});
    // 与其它图层一致地重推一次:creationParams 是首帧快照,视图创建完成前 widget
    // 可能已经重建过(定位回调常在此窗口内到达)。
    _viewChannel
        ?.invokeMethod<void>('updateMyLocation', <String, Object?>{
          'showMyLocation': widget.showMyLocation,
        })
        .catchError((Object _) {});
    _updateNativeVisibility();
    widget.onMapCreated?.call(id);
  }

  void _updateNativeVisibility() {
    _viewChannel
        ?.invokeMethod<void>('setVisible', <String, Object?>{
          'visible': widget.visible,
        })
        .catchError((Object _) {});
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
}
