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
