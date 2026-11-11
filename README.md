# amap_native_plugin

在 Flutter 中嵌入原生高德地图，提供 Android、iOS、HarmonyOS 的基础地图渲染和交互。
本仓库不依赖 Pawrio App，示例与验证也不要求 App 可集成运行。
本轮工作分支为 `adapt/amap-0.1.3-ohos-core`，基于现有 0.1.3 源码提交 `8d8560c`，保留原 Git 历史。

## 职责边界

保留：地图展示、相机移动/缩放、点/线/圆覆盖物、点击与相机事件、自定义 marker 图片、原生地图 PNG 截图、可见性和生命周期。

宿主负责：SDK Key、用户隐私同意、运行时权限、页面路由、定位业务与数据上传、轨迹采集/回放调度、围栏告警、分享卡片和第三方分享。
地点搜索、逆地理编码属于地理搜索服务；本轮移除 `searchPlaces` / `AmapPlace`，不把 App 副本新增的 `reverseGeocode` 迁入地图核心。
`shouldUseNativeMap` / `isMapRendererSupported` 的模拟器启发式也不作为插件能力；它不能证明设备实际渲染结果。

`AmapCircleGeofence` 保留已有类型名称，但只表示圆形绘制参数及 `contains` 几何计算，不注册系统围栏，不产生进出事件。
`showMyLocation` 控制地图 SDK 的蓝点图层，不提供独立的前台/后台定位服务。

## 源码结构

```text
lib/
  amap_native_plugin.dart                    # 公共入口及初始化
  amap_native_plugin_platform_interface.dart # 平台协议
  amap_native_plugin_method_channel.dart     # SDK 初始化通道
  src/
    models/map_overlays.dart                 # 坐标、marker、polyline、circle
    map_controller.dart                      # 相机与截图控制
    map_view.dart                            # PlatformView、事件、可见性
    marker_renderer.dart                     # Flutter marker 转 PNG
    ohos/amap_ohos.dart                       # 鸿蒙专属 Flutter 视图入口
android/.../amap_native_plugin/
  AmapNativePlugin.kt                        # 注册与初始化
  AmapMapViewFactory.kt                      # 创建与宿主生命周期
  AmapPlatformMapView.kt                     # 相机、事件、方法通道
  NativeMapView.kt                           # Surface / Texture 适配
  AmapOverlayController.kt                   # 覆盖物管理
  AmapPinRenderer.kt                         # 标记图像合成
  AmapSnapshotController.kt                  # 有限时、一次完成的截图请求
ios/.../amap_native_plugin/
  AmapNativePlugin.swift
  AmapMapViewFactory.swift
  AmapPlatformMapView.swift
  AmapOverlayController.swift
  AmapPinRenderer.swift
  AmapSnapshotController.swift
ohos/
  src/main/ets/                             # 原生注册、视图、覆盖物与标记
```

鸿蒙 Dart 入口通过 `dartPluginClass` / `dartFileName` 自动注册，主入口不导入 `OhosView`，
使 Android/iOS 的 Dart 编译链不引用鸿蒙专属 Flutter 符号。这个入口需由社区鸿蒙 Flutter SDK 编译；
通用分析排除该专属文件，鸿蒙 HAP 构建单独校验它。

## 初始化与最小使用

宿主完成高德隐私说明和用户同意后，先初始化再创建地图。隐私参数默认 false，不由插件替宿主决定：

```dart
WidgetsFlutterBinding.ensureInitialized();
await AmapNative.init(
  androidApiKey: androidKey,
  iosApiKey: iosKey,
  ohosApiKey: harmonyKey,
  privacyShown: true,
  privacyAgreed: true,
);
```

三个平台使用各自申请的移动 SDK Key。鸿蒙 Key 对应宿主包名、签名及高德开放平台配置；不使用 Web Service Key。
旧 `androidPrivacyShown` / `androidPrivacyAgreed` 参数保留为弃用兼容参数，新接入使用通用参数。
0.1.4 移除搜索和设备策略 API，并将隐私状态默认值改为 false，包含不兼容变化。
当前公开包名为 amap_native_plugin，版本 0.1.4；省略 publish_to，发布时使用 PUB_HOSTED_URL=https://pub.dev。

```dart
AmapMapController? controller;

AmapMapView(
  initialCenter: const AmapLatLng(31.2304, 121.4737),
  initialZoom: 12,
  onMapCreated: (id) => controller = AmapMapController(id),
  pins: const [
    AmapMapPin(
      position: AmapLatLng(31.2304, 121.4737),
      label: 'Point A',
    ),
  ],
  polylines: const [
    AmapMapPolyline(
      points: [AmapLatLng(31.2304, 121.4737), AmapLatLng(31.2404, 121.4837)],
      dashed: true,
    ),
  ],
  circleGeofences: const [
    AmapCircleGeofence(center: AmapLatLng(31.2304, 121.4737), radiusMeters: 500),
  ],
  onMapTap: (position) { /* host interaction */ },
);

await controller?.moveCamera(center: const AmapLatLng(31.24, 121.48), zoom: 14);
await controller?.zoomBy(1);
await controller?.fitAllOverlays(padding: 48);
final png = await controller?.takeSnapshot();
```

地图必须得到有限且非零的布局尺寸。`initialCenter` / `initialZoom` 用于创建时状态，运行中相机移动使用 controller。
`pins`、`polylines`、`circleGeofences` 以新列表更新；`visible=false` 保留实例并停止交互，原生层与宿主前后台状态共同控制渲染。
`useTextureView` 是 Android 创建时参数，实例创建后需显式重建才能改变。
`zoomControlsEnabled` 控制 Android SDK 的缩放控件；iOS/HarmonyOS 用 `zoomBy` 自行组合 Flutter 控件。

自定义 marker 的 `child` 应有明确尺寸，会转换为 PNG。子组件异步图片重绘会触发补刷；同一时刻只有一个整组截图任务，
持续重绘不会并发堆积或使每个结果都过期。定义改变与已销毁视图的旧结果被丢弃。
图像转换错误通过 Flutter 错误通道报告，保留既有图像或原生默认 marker。

截图只包含原生 SDK 地图与覆盖物，不包含 Flutter 按钮、`centerPin`、弹窗和分享卡片。
SDK 无图或超时返回 null；地图未就绪、隐藏、销毁或截图并发时通过平台错误报告。
瓦片、图片标记及最终视觉效果需用有效 Key 在真机验证，编译通过不代替地图验收。

## 平台依赖与宿主配置

### Android

当前沿用已固定的厂商合包：

```kotlin
implementation("com.amap.api:3dmap-location-search:11.1.200_loc11.1.200_sea9.7.4")
```

插件不暴露搜索 API；厂商 JAR 合包仍包含其组件。本次核对 Maven Central 的纯 `3dmap` 元数据，
未发现相同 11.1.200 版本，因此没有为减小依赖而静默降级 SDK。SDK 升级或切换纯地图发行物需另行验证。
consumer R8 规则随插件提供，保留实际需要的反射、JNI 和已知可选依赖规则，不迁入 App 的 Gradle/Kotlin 降级配置。
宿主需提供网络权限；使用蓝点时自行申请位置权限。初始化 Key 可以代替 Manifest 中的默认 Key 配置。

### iOS

CocoaPods 依赖 `AMap3DMap` 与 Flutter；本轮移除 `AMapSearch` 依赖。
使用地图蓝点前，宿主配置 Info.plist 位置用途并取得权限。插件不会弹宿主隐私流程或启动后台定位。
本轮仅完成 Swift 语法检查，没有进行 iOS 构建和真机验收。

### HarmonyOS

使用社区 Flutter `ohos/3.44.9+ohos-1.0.0-beta`、DevEco Studio 和高德官方 OHPM SDK。
地图、common、location 依赖固定为 `11.2.1`；由 OHPM 解析，SDK HAR 与原生二进制不提交到仓库。
地图 SDK 依赖 location 组件，不等于插件提供独立定位 API。
每个 PlatformView 有独立名称、通道和覆盖物状态，SDK 全局回调按名称过滤，并在销毁时注销。

宿主 module.json5 至少声明：

```json
{"module":{"requestPermissions":[{"name":"ohos.permission.INTERNET"}]}}
```

使用蓝点时，另按宿主业务声明并在使用时申请 LOCATION / APPROXIMATELY_LOCATION。
插件不统一申请麦克风、相机、蓝牙、图库等与基础地图无关的权限。
原生 MapView 与宿主/视图生命周期同步；PNG 截图限制为一个在途请求，最长等待 5 秒，销毁时结束挂起请求。
无效或缺失鸿蒙 Key、未同意隐私、未就绪地图均返回明确错误。

## App 副本差异结论

对比来源为相邻 Pawrio App 的 `third_party/amap_native_plugin`，只迁移可独立复用的正确性修复：

| 差异 | 本轮处理 |
| --- | --- |
| 折线 dashed | 迁入 Dart 及各平台基础线覆盖物 |
| 异步 child marker 首帧后重绘 | 迁入，并补单任务执行与空尺寸保护 |
| reverseGeocode / AmapRegeocode | 不迁入；属于地理搜索服务 |
| isMapRendererSupported 改名 | 不迁入；移除模拟器启发式策略 |
| release debugNeedsPaint 防护、相机状态回写、TextureMapView、标签缩放及定位 | 主仓库已有，保留修复 |
| App 的单一生命周期状态 | 不覆盖主仓库已有的 hostActive / requestedVisible 双状态管理 |
| App 工具链版本、宠物状态颜色语义、设备/接口与业务流程 | 不迁入 |

## 验证与发布

验证范围为插件和隔离探针，正式 App 集成与有效 Key 真机验收分别进行。
当前例子中的已有 UI 改动保留；未为 App 集成回退保留搜索 API。

```sh
# 使用已安装的 Flutter SDK，在插件根目录运行
flutter pub get --no-example
flutter test --no-pub
dart analyze lib test
# 独立 example 沿用原有 Android/iOS 宿主
cd example
flutter run --dart-define=AMAP_ANDROID_API_KEY=... --dart-define=AMAP_IOS_API_KEY=...
```

鸿蒙采用隔离的最小宿主进行 HAP 编译，校验 Dart 自动注册、原生 PlatformView 和高德动态库打包。
该探针使用本机调试签名、仅用于构建；若包名复用现有应用，不应直接覆盖安装。

当前验证包括 17 项插件测试、2 项示例测试、通用 Dart 静态分析、Swift 语法检查和隔离鸿蒙 HAP 编译。
Android/iOS 构建以及有效 Key 的地图展示、相机/覆盖物/截图、生命周期真机验收仍待完成。
公开发布使用 `PUB_HOSTED_URL=https://pub.dev dart pub publish --dry-run`，审核归档后执行同来源的 `dart pub publish`。
`.pubignore` 排除本地发布脚本、FVM、IDE、SDK HAR 和构建缓存。

## 官方参考

- [高德 HarmonyOS 地图创建指南](https://developer.amap.com/api/harmonyosnext-map3d-sdk/guide/create-map/show-map)
- [高德 HarmonyOS 地图 SDK API](https://a.amap.com/lbs-dev-yuntu/static/reference/harmonyosnext-sdk/map/docs/mapDocs/classes/AMap.AMap.html)
- [Android 纯地图发行物元数据](https://repo.maven.apache.org/maven2/com/amap/api/3dmap/maven-metadata.xml)
