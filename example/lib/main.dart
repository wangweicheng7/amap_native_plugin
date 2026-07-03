import 'package:amap_native_plugin/amap_native_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  AmapNative.init(
    androidApiKey: const String.fromEnvironment('AMAP_ANDROID_API_KEY'),
    iosApiKey: const String.fromEnvironment('AMAP_IOS_API_KEY'),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const GeofenceDemoPage(),
    );
  }
}

class GeofenceDemoPage extends StatefulWidget {
  const GeofenceDemoPage({super.key});

  @override
  State<GeofenceDemoPage> createState() => _GeofenceDemoPageState();
}

class _GeofenceDemoPageState extends State<GeofenceDemoPage> {
  static const _initialCenter = AmapLatLng(30.2741, 120.1551);
  static const _minRadius = 10.0;
  static const _maxRadius = 1500.0;

  AmapLatLng _center = _initialCenter;
  double _radiusMeters = 500;
  bool _isDraggingMap = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('地理围栏半径调节')),
      body: Column(
        children: [
          Expanded(
            child: AmapMapView(
              initialCenter: _initialCenter,
              initialZoom: 14,
              centerPin: const _CenterPin(color: Color(0xFF2563EB)),
              movingCenterPin: const _CenterPin(color: Color(0xFFF97316)),
              onCameraMove: (_) {
                if (_isDraggingMap) {
                  return;
                }

                setState(() {
                  _isDraggingMap = true;
                });
              },
              onCameraIdle: (center) {
                setState(() {
                  _center = center;
                  _isDraggingMap = false;
                });
              },
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
              },
              circleGeofences: _isDraggingMap
                  ? const <AmapCircleGeofence>[]
                  : [
                      AmapCircleGeofence(
                        center: _center,
                        radiusMeters: _radiusMeters,
                        strokeColor: const Color(0xFF2563EB),
                        fillColor: const Color(0x332563EB),
                        strokeWidth: 4,
                      ),
                    ],
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '地理围栏半径',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_radiusMeters.round()}m',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 24),
                    Slider(
                      min: _minRadius,
                      max: _maxRadius,
                      divisions: 149,
                      label: '${_radiusMeters.round()}m',
                      value: _radiusMeters,
                      onChanged: (value) {
                        setState(() {
                          _radiusMeters = value;
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [Text('10m'), Text('1500m')],
                    ),
                    const Spacer(),
                    Text(
                      _isDraggingMap
                          ? '正在移动地图，松手后会按屏幕中心重绘围栏。'
                          : '上方地图支持手动拖动和双指缩放。拖动滑块会实时更新圆形围栏大小。',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '中心点：${_center.latitude.toStringAsFixed(6)}, '
                      '${_center.longitude.toStringAsFixed(6)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterPin extends StatelessWidget {
  const _CenterPin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -18),
      child: Icon(
        Icons.location_pin,
        color: color,
        size: 44,
        shadows: const [
          Shadow(blurRadius: 6, color: Color(0x55000000), offset: Offset(0, 2)),
        ],
      ),
    );
  }
}
