part of '../amap_native_plugin.dart';

extension _AmapPinRendering on _AmapMapViewState {
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
          child: _PinRepaintBoundary(
            key: _pinRenderKeys[index],
            onPainted: _onPinPainted,
            child: child,
          ),
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

  void _onPinPainted() {
    _schedulePinRendering();
  }

  void _schedulePinRendering() {
    _pinRenderDirty = true;
    if (_pinRenderScheduled || _pinRenderingActive || !mounted) return;
    _pinRenderScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinRenderScheduled = false;
      if (!mounted) return;
      unawaited(_renderPinsSerially());
    });
  }

  Future<void> _renderPinsSerially() async {
    if (_pinRenderingActive || !mounted) return;
    _pinRenderingActive = true;
    _pinRenderDirty = false;
    try {
      await _renderPins(_pinRenderGeneration);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'amap_native_plugin',
          context: ErrorDescription('while rendering a custom map marker'),
        ),
      );
    } finally {
      _pinRenderingActive = false;
      if (mounted && _pinRenderDirty) _schedulePinRendering();
    }
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
      // debugNeedsPaint is only available when assertions are enabled.
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
      if (logicalSize.isEmpty) continue;
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

class _PinRepaintBoundary extends SingleChildRenderObjectWidget {
  const _PinRepaintBoundary({
    required this.onPainted,
    required super.child,
    super.key,
  });

  final VoidCallback onPainted;

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _RenderPinRepaintBoundary(onPainted);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPinRepaintBoundary renderObject,
  ) {
    renderObject.onPainted = onPainted;
  }
}

class _RenderPinRepaintBoundary extends RenderRepaintBoundary {
  _RenderPinRepaintBoundary(this.onPainted);

  VoidCallback onPainted;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPainted();
  }
}

class _RenderedPin {
  const _RenderedPin(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final double width;
  final double height;
}
