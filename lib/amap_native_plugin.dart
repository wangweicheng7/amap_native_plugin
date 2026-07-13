import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
  });

  final AmapLatLng position;
  final String? title;
  final String? snippet;
  final bool draggable;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'position': position.toJson(),
      'title': title,
      'snippet': snippet,
      'draggable': draggable,
    };
  }
}

class AmapMapPolyline {
  const AmapMapPolyline({
    required this.points,
    this.color = const Color(0xFFFF5B00),
    this.width = 6,
  });

  final List<AmapLatLng> points;
  final Color color;
  final double width;

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
    return widget.pins.map((pin) => pin.toJson()).toList(growable: false);
  }

  List<Map<String, Object?>> get _polylinesJson {
    return widget.polylines
        .map((polyline) => polyline.toJson())
        .toList(growable: false);
  }

  @override
  void didUpdateWidget(covariant AmapMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_viewChannel == null) {
      return;
    }

    if (!listEquals(oldWidget.circleGeofences, widget.circleGeofences)) {
      _viewChannel?.invokeMethod<void>(
        'updateCircleGeofences',
        <String, Object?>{'circleGeofences': _circleGeofencesJson},
      );
    }

    if (!listEquals(oldWidget.pins, widget.pins)) {
      _viewChannel?.invokeMethod<void>('updatePins', <String, Object?>{
        'pins': _pinsJson,
      });
    }

    if (!listEquals(oldWidget.polylines, widget.polylines)) {
      _viewChannel?.invokeMethod<void>('updatePolylines', <String, Object?>{
        'polylines': _polylinesJson,
      });
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
      return _withCenterPin(view);
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _withCenterPin(view),
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
}
