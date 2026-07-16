import 'dart:async';
import 'dart:math' as math;

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
      home: const ExamplesHomePage(),
    );
  }
}

class ExamplesHomePage extends StatelessWidget {
  const ExamplesHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AMap Native Plugin Examples')),
      body: ListView(
        children: [
          ExampleListTile(
            title: '基础地图',
            subtitle: '展示一个可交互的原生高德地图。',
            builder: (_) => const BasicMapPage(),
          ),
          ExampleListTile(
            title: '固定尺寸地图',
            subtitle: '把地图作为固定宽高的小组件嵌入页面。',
            builder: (_) => const FixedSizeMapPage(),
          ),
          ExampleListTile(
            title: '圆形地理围栏',
            subtitle: '绘制中心点和半径固定的圆形围栏。',
            builder: (_) => const StaticGeofencePage(),
          ),
          ExampleListTile(
            title: '地图中心围栏编辑',
            subtitle: '拖动地图选择中心点，滑块实时调整围栏半径。',
            builder: (_) => const GeofenceEditorPage(),
          ),
          ExampleListTile(
            title: '地图大头针放置',
            subtitle: '点击地图在原生层放置一个大头针。',
            builder: (_) => const PinPlacementPage(),
          ),
          ExampleListTile(
            title: '围栏大头针示例',
            subtitle: '一个地理围栏，围栏内外各放置大头针。',
            builder: (_) => const GeofencePinDemoPage(),
          ),
          ExampleListTile(
            title: '动态轨迹与移动大头针',
            subtitle: '逐点绘制轨迹，大头针始终跟随轨迹末端移动。',
            builder: (_) => const DynamicTrackPage(),
          ),
          ExampleListTile(
            title: '三围栏随机大头针判断',
            subtitle: '绘制三个围栏，随机放置大头针并判断是否位于围栏内。',
            builder: (_) => const RandomPinGeofencePage(),
          ),
        ],
      ),
    );
  }
}

class ExampleListTile extends StatelessWidget {
  const ExampleListTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
      },
    );
  }
}

class BasicMapPage extends StatelessWidget {
  const BasicMapPage({super.key});

  static const _center = AmapLatLng(31.2304, 121.4737);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('基础地图')),
      body: const AmapMapView(initialCenter: _center, initialZoom: 12),
    );
  }
}

class FixedSizeMapPage extends StatelessWidget {
  const FixedSizeMapPage({super.key});

  static const _center = AmapLatLng(39.9042, 116.4074);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('固定尺寸地图')),
      body: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: const AmapMapView(
            width: 280,
            height: 180,
            initialCenter: _center,
            initialZoom: 11,
          ),
        ),
      ),
    );
  }
}

class StaticGeofencePage extends StatelessWidget {
  const StaticGeofencePage({super.key});

  static const _center = AmapLatLng(30.2741, 120.1551);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('圆形地理围栏')),
      body: const AmapMapView(
        initialCenter: _center,
        initialZoom: 13,
        centerPin: _CenterPin(color: Color(0xFF2563EB)),
        circleGeofences: [
          AmapCircleGeofence(
            center: _center,
            radiusMeters: 800,
            strokeColor: Color(0xFF2563EB),
            fillColor: Color(0x332563EB),
            strokeWidth: 4,
          ),
          AmapCircleGeofence(
            center: AmapLatLng(30.289, 120.166),
            radiusMeters: 500,
            strokeColor: Color(0xFF16A34A),
            fillColor: Color(0x3316A34A),
            strokeWidth: 3,
          ),
        ],
      ),
    );
  }
}

class GeofenceEditorPage extends StatefulWidget {
  const GeofenceEditorPage({super.key});

  @override
  State<GeofenceEditorPage> createState() => _GeofenceEditorPageState();
}

class _GeofenceEditorPageState extends State<GeofenceEditorPage> {
  static const _initialCenter = AmapLatLng(30.2741, 120.1551);
  static const _minRadius = 10.0;
  static const _maxRadius = 1500.0;

  AmapLatLng _center = _initialCenter;
  double _radiusMeters = 500;
  bool _isDraggingMap = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('地图中心围栏编辑')),
      body: Column(
        children: [
          Expanded(
            child: AmapMapView(
              initialCenter: _initialCenter,
              initialZoom: 14,
              centerPin: const _CenterPin(color: Color(0xFF2563EB)),
              // movingCenterPin: const _CenterPin(color: Color(0xFFF97316)),
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

class PinPlacementPage extends StatefulWidget {
  const PinPlacementPage({super.key});

  @override
  State<PinPlacementPage> createState() => _PinPlacementPageState();
}

class _PinPlacementPageState extends State<PinPlacementPage> {
  static const _initialCenter = AmapLatLng(31.2304, 121.4737);
  AmapLatLng? _pin;

  @override
  Widget build(BuildContext context) {
    final pins = _pin == null
        ? const <AmapMapPin>[]
        : <AmapMapPin>[
            AmapMapPin(position: _pin!, title: '已放置大头针', snippet: '点击地图可重新放置'),
          ];

    return Scaffold(
      appBar: AppBar(title: const Text('地图大头针放置')),
      body: Column(
        children: [
          Expanded(
            child: AmapMapView(
              initialCenter: _initialCenter,
              initialZoom: 12,
              pins: pins,
              onMapTap: (position) {
                setState(() {
                  _pin = position;
                });
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _pin == null
                          ? '点击地图任意位置放置一个大头针。'
                          : '大头针：${_pin!.latitude.toStringAsFixed(6)}, ${_pin!.longitude.toStringAsFixed(6)}',
                    ),
                  ),
                  if (_pin != null)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _pin = null;
                        });
                      },
                      child: const Text('清除'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GeofencePinDemoPage extends StatefulWidget {
  const GeofencePinDemoPage({super.key});

  @override
  State<GeofencePinDemoPage> createState() => _GeofencePinDemoPageState();
}

class _GeofencePinDemoPageState extends State<GeofencePinDemoPage> {
  static const _center = AmapLatLng(30.2741, 120.1551);
  static const _insidePin = AmapMapPin(
    position: AmapLatLng(30.2747, 120.1558),
    title: '围栏内',
    snippet: '位于地理围栏内部',
  );
  static const _outsidePinOne = AmapMapPin(
    position: AmapLatLng(30.286, 120.165),
    title: '围栏外 1',
    snippet: '位于地理围栏外部',
    label: '自定义提示文字',
    pinColor: Color(0xFF7C3AED),
    labelTextColor: Color(0xFFFFFFFF),
    labelBackgroundColor: Color(0xE67C3AED),
  );
  static const _outsidePinTwo = AmapMapPin(
    position: AmapLatLng(30.264, 120.142),
    title: '围栏外 2',
    snippet: '位于地理围栏外部',
  );
  static const _imagePin = AmapMapPin(
    position: AmapLatLng(30.269, 120.169),
    title: '自定义 Widget 大头针',
    snippet: 'Flutter Widget 会转换为图片并显示在原生地图上',
    child: SizedBox(
      width: 54,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF0F766E),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Icon(Icons.pets, color: Colors.white, size: 30),
      ),
    ),
  );
  static const _focusZoom = 15.0;

  AmapMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('围栏大头针示例')),
      body: Column(
        children: [
          Expanded(
            child: AmapMapView(
              initialCenter: _center,
              initialZoom: 13,
              onMapCreated: (mapId) {
                setState(() {
                  _mapController = AmapMapController(mapId);
                });
              },
              circleGeofences: const [
                AmapCircleGeofence(
                  center: _center,
                  radiusMeters: 900,
                  strokeColor: Color(0xFF2563EB),
                  fillColor: Color(0x332563EB),
                  strokeWidth: 4,
                ),
              ],
              pins: const [
                _insidePin,
                _outsidePinOne,
                _outsidePinTwo,
                _imagePin,
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('蓝色圆形为地理围栏；紫色针体和 Flutter Widget 展示两种自定义大头针样式。'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _mapController == null
                              ? null
                              : () => _mapController!.moveCamera(
                                  center: _insidePin.position,
                                  zoom: _focusZoom,
                                ),
                          icon: const Icon(Icons.my_location),
                          label: const Text('定位按钮'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _mapController == null
                              ? null
                              : () => _mapController!.fitAllOverlays(),
                          icon: const Icon(Icons.zoom_out_map),
                          label: const Text('定位按钮 2'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DynamicTrackPage extends StatefulWidget {
  const DynamicTrackPage({super.key});

  @override
  State<DynamicTrackPage> createState() => _DynamicTrackPageState();
}

class RandomPinGeofencePage extends StatefulWidget {
  const RandomPinGeofencePage({super.key});

  @override
  State<RandomPinGeofencePage> createState() => _RandomPinGeofencePageState();
}

class _RandomPinGeofencePageState extends State<RandomPinGeofencePage> {
  static const _mapCenter = AmapLatLng(30.2755, 120.1600);
  static const _geofences = <_DemoGeofence>[
    _DemoGeofence(
      name: '西湖围栏',
      center: AmapLatLng(30.2741, 120.1551),
      radiusMeters: 700,
      strokeColor: Color(0xFF2563EB),
      fillColor: Color(0x332563EB),
    ),
    _DemoGeofence(
      name: '北区围栏',
      center: AmapLatLng(30.2830, 120.1640),
      radiusMeters: 600,
      strokeColor: Color(0xFF16A34A),
      fillColor: Color(0x3316A34A),
    ),
    _DemoGeofence(
      name: '南区围栏',
      center: AmapLatLng(30.2670, 120.1690),
      radiusMeters: 550,
      strokeColor: Color(0xFFF97316),
      fillColor: Color(0x33F97316),
    ),
  ];

  late final AmapLatLng _randomPin;
  late final List<_DemoGeofence> _containingGeofences;

  @override
  void initState() {
    super.initState();
    final random = math.Random();
    _randomPin = AmapLatLng(
      30.2600 + random.nextDouble() * 0.031,
      120.1430 + random.nextDouble() * 0.034,
    );
    _containingGeofences = _geofences
        .where((geofence) => geofence.contains(_randomPin))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final isInside = _containingGeofences.isNotEmpty;
    final resultText = isInside
        ? '判断结果：位于 ${_containingGeofences.map((item) => item.name).join('、')} 内'
        : '判断结果：不在任何围栏内';
    return Scaffold(
      appBar: AppBar(title: const Text('三围栏随机大头针判断')),
      body: Column(
        children: [
          Expanded(
            child: AmapMapView(
              initialCenter: _mapCenter,
              initialZoom: 13.8,
              circleGeofences: _geofences
                  .map((geofence) => geofence.overlay)
                  .toList(growable: false),
              pins: [
                AmapMapPin(
                  position: _randomPin,
                  title: '随机大头针',
                  snippet: resultText,
                  label: isInside ? '围栏内' : '围栏外',
                  pinColor: isInside
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  labelBackgroundColor: isInside
                      ? const Color(0xE616A34A)
                      : const Color(0xE6DC2626),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    resultText,
                    key: const ValueKey<String>('geofence-result'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '随机坐标：${_randomPin.latitude.toStringAsFixed(6)}, '
                    '${_randomPin.longitude.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoGeofence {
  const _DemoGeofence({
    required this.name,
    required this.center,
    required this.radiusMeters,
    required this.strokeColor,
    required this.fillColor,
  });

  final String name;
  final AmapLatLng center;
  final double radiusMeters;
  final Color strokeColor;
  final Color fillColor;

  AmapCircleGeofence get overlay {
    return AmapCircleGeofence(
      center: center,
      radiusMeters: radiusMeters,
      strokeColor: strokeColor,
      fillColor: fillColor,
      strokeWidth: 3,
    );
  }

  bool contains(AmapLatLng point) {
    return overlay.contains(point);
  }
}

class _DynamicTrackPageState extends State<DynamicTrackPage> {
  static const _track = <AmapLatLng>[
    AmapLatLng(30.2741, 120.1551),
    AmapLatLng(30.2750, 120.1560),
    AmapLatLng(30.2758, 120.1572),
    AmapLatLng(30.2766, 120.1580),
    AmapLatLng(30.2774, 120.1570),
    AmapLatLng(30.2782, 120.1558),
    AmapLatLng(30.2790, 120.1568),
  ];
  static const _movingPin = AmapMapPin(
    position: AmapLatLng(30.2741, 120.1551),
    title: '当前轨迹位置',
    label: '移动中',
    pinColor: Color(0xFF16A34A),
    labelBackgroundColor: Color(0xE616A34A),
  );

  Timer? _timer;
  int _visiblePointCount = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _visiblePointCount = _visiblePointCount == _track.length
            ? 1
            : _visiblePointCount + 1;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visiblePoints = _track.sublist(0, _visiblePointCount);
    return Scaffold(
      appBar: AppBar(title: const Text('动态轨迹与移动大头针')),
      body: AmapMapView(
        initialCenter: _track.first,
        initialZoom: 16,
        polylines: <AmapMapPolyline>[
          AmapMapPolyline(
            points: visiblePoints,
            color: const Color(0xFFFF5B00),
            width: 6,
            movingPin: _movingPin,
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
