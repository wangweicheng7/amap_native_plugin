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

typedef AmapCameraChangedCallback = void Function(AmapLatLng center);

class AmapMapView extends StatefulWidget {
  const AmapMapView({
    super.key,
    this.width,
    this.height,
    this.initialCenter,
    this.initialZoom,
    this.circleGeofences = const <AmapCircleGeofence>[],
    this.showMyLocation = false,
    this.centerPin,
    this.movingCenterPin,
    this.onCameraMove,
    this.onCameraIdle,
    this.gestureRecognizers,
    this.onMapCreated,
  });

  final double? width;
  final double? height;
  final AmapLatLng? initialCenter;
  final double? initialZoom;
  final List<AmapCircleGeofence> circleGeofences;
  final bool showMyLocation;
  final Widget? centerPin;
  final Widget? movingCenterPin;
  final AmapCameraChangedCallback? onCameraMove;
  final AmapCameraChangedCallback? onCameraIdle;
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
      'showMyLocation': widget.showMyLocation,
    };
  }

  List<Map<String, Object?>> get _circleGeofencesJson {
    return widget.circleGeofences
        .map((geofence) => geofence.toJson())
        .toList(growable: false);
  }

  @override
  void didUpdateWidget(covariant AmapMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_viewChannel == null ||
        listEquals(oldWidget.circleGeofences, widget.circleGeofences)) {
      return;
    }

    _viewChannel?.invokeMethod<void>('updateCircleGeofences', <String, Object?>{
      'circleGeofences': _circleGeofencesJson,
    });
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
