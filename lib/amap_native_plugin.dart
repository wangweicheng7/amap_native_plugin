import 'dart:async';
import 'dart:io';
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
    this.pinColor = const Color(0xFFF97316),
    this.labelTextColor = Colors.white,
    this.labelBackgroundColor = const Color(0xE62D3748),
    this.child,
  });

  final AmapLatLng position;
  final String? title;
  final String? snippet;
  final bool draggable;
  final String? label;
  final Color pinColor;
  final Color labelTextColor;
  final Color labelBackgroundColor;
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
      );
    }

    if (pinDefinitionsChanged) {
      _resetPinRenderState();
      _schedulePinRendering();
    }

    if (!listEquals(oldWidget.polylines, widget.polylines)) {
      _viewChannel?.invokeMethod<void>('updatePolylines', <String, Object?>{
        'polylines': _polylinesJson,
      });
      if (!pinDefinitionsChanged && _movingPinUpdatesJson.isNotEmpty) {
        _viewChannel?.invokeMethod<void>('updateMovingPins', <String, Object?>{
          'updates': _movingPinUpdatesJson,
        });
      }
    }
  }

  @override
  void dispose() {
    _viewChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget view;
    if (Platform.isAndroid) {
      view = AndroidView(
        viewType: AmapMapView._viewType,
        creationParams: _creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: widget.gestureRecognizers,
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else if (Platform.isIOS) {
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

    if (widget.width == null && widget.height == null) {
      return _withPinRenderers(_withCenterPin(view));
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _withPinRenderers(_withCenterPin(view)),
    );
  }

  void _onPlatformViewCreated(int id) {
    _viewChannel = MethodChannel('amap_native_plugin/map_view_$id');
    _viewChannel?.setMethodCallHandler(_handlePlatformViewCall);
    _viewChannel?.invokeMethod<void>('updateCircleGeofences', <String, Object?>{
      'circleGeofences': _circleGeofencesJson,
    });
    _viewChannel?.invokeMethod<void>('updatePins', <String, Object?>{
      'pins': _pinsJson,
    });
    _schedulePinRendering();
    _viewChannel?.invokeMethod<void>('updatePolylines', <String, Object?>{
      'polylines': _polylinesJson,
    });
    widget.onMapCreated?.call(id);
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
    if (pin == null) {
      return mapView;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        mapView,
        IgnorePointer(child: Center(child: pin)),
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
    if (renderers.isEmpty) {
      return mapView;
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ...renderers,
        Positioned.fill(child: mapView),
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
      if (renderObject is! RenderRepaintBoundary ||
          renderObject.debugNeedsPaint) {
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
    await _viewChannel?.invokeMethod<void>('updatePins', <String, Object?>{
      'pins': _pinsJson,
    });
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
