part of '../amap_native_plugin.dart';

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
