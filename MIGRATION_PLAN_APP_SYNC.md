# amap_native_plugin 同步迁移方案（评审修订版）

更新日期：2026-09-11。状态：已根据用户授权完成技术决策；本轮仅更新方案，尚未实施源码迁移、提交、发布或切换 App 依赖。

## 一、依据及前次审查更正

主仓库：`/Users/wangweicheng/Documents/origin/amap_native_plugin`（本轮基线 main，0.1.2）。
来源：`/Users/wangweicheng/Documents/origin/origin_app_flu/third_party/amap_native_plugin`，App HEAD 为 `278d7ad672ebe775736582c6ee569d7a4f60328b`。

副本没有独立 Git，但受 App 仓库版本控制，可以追溯修改历史。前次审查仅做文件对比，没有充分利用这段历史。App 注释和历史记录反映当时修复意图，不等于本轮真机验证结果。

关键证据（以下路径相对 App 根目录）：

| 证据 | 需求 |
|---|---|
| 提交 `5208e197`：use texture map to prevent keyboard flicker | TextureMapView 用于修复键盘引起的地图闪烁 |
| 提交 `2fbcff3a`：prevent Android map disposal ANR | 防止地图销毁与视图 detach 的时序问题 |
| 提交 `37d8df70`：keep native view stable across overlay updates | 覆盖物变化不能导致 PlatformView 重建 |
| 提交 `21e9558e`、`6d3eff4c` | 围栏圆弧精度、双端虚线样式；前版方案遗漏，纳入范围 |
| `lib/features/location/presentation/location/widgets/location_map_stage.dart:173` | 首页地图显式使用 TextureView，离屏保留实例并暂停渲染 |
| `lib/features/location/presentation/track_replay/track_replay_page.dart:639` | 分享前调整相机、等待 cameraIdle，再等待 Flutter 帧 |
| `lib/features/location/presentation/track_replay/track_replay_controller_action.dart:105` | 调用原生 takeSnapshot |
| `lib/features/location/presentation/widgets/bottom_sheets/track_replay_share_bottom_sheet.dart:149` | 解码地图 PNG，用 RawImage 合成卡片，再用 RepaintBoundary 导出 |
| `lib/features/location/presentation/find_pet/find_pet_page.dart:202` | 寻宠页面关闭 SDK 缩放按钮，使用业务控件 |
| `test/features/location/presentation/location_page_test.dart` | 已有地图保活、可见性、TextureView 测试 |

Android 当前 setVisible 实际调用 onPause/onResume，并非通过 GONE/INVISIBLE 隐藏；iOS 当前只设 isHidden。Flutter 的透明度、交互屏蔽与 Android 的暂停是不同职责，不应一概判为冗余。当前真正的问题是生命周期状态来源没有分开。

## 二、七项最终设计决策

### 1. Android 默认 TextureMapView

默认 `useTextureView: true`，保留 false 回退；它是创建时参数，实例创建后更改须显式重建，不静默忽略。

理由：App 有键盘、Tab 保活、路由叠加和多个地图实例共存场景；已有修复提交直接指向键盘闪烁。高德文档说明 TextureMapView 在与其他 GL 视图共存及滑动容器中有合成优势。这个选择针对当前场景，不宣称所有设备性能更优。

高德视图类型和 Flutter PlatformView 合成方式是两层决策。不能只更换高德 MapView，就宣称 Flutter 合成模式一定正确。基于当前 Flutter SDK 分别验证 AndroidView 和原有 PlatformViewLink 路径，选通过键盘、叠层、手势、销毁测试的实现，避免新增第二个公共合成模式开关。

### 2. visible 保留实例，并控制交互和渲染活跃状态

`visible=false`：不接收点击、不显示地图、暂停原生渲染，不销毁实例。恢复后沿用相机和覆盖物。

内部状态分别保存：hostActive、requestedVisible、disposed。实际渲染条件为 `hostActive && requestedVisible && !disposed`，只有条件发生变化才调用原生 resume/pause。Activity 回到前台不得恢复 requestedVisible=false 的地图；隐藏页收到 visible=true 也不得绕过后台限制。

Android 不主动通过 GONE/INVISIBLE 销毁渲染 Surface。iOS 不能仅用 isHidden 就声称已停止绘制，应核查当前安装 SDK 的渲染暂停 API及恢复行为，再完成等价实现；不能用停止地图元素创建的配置替代暂停绘制。

### 3. 地图截图由原生 SDK 提供，Flutter 合成最终分享图

Flutter 可以导出自身绘制的内容，但不能把 RepaintBoundary.toImage 包裹 PlatformView 当成双端可靠地图截图方案；iOS 原生 UIView 独立参与合成，Android 也受合成路径影响。改用 TextureMapView 不等于获得跨平台 Flutter 截图保证。

沿用 App 已采用的两段流程：原生地图 PNG → Flutter RawImage 加文字、数据和业务 UI → RepaintBoundary 导出分享卡片。

插件 `takeSnapshot()` 的契约：

- 返回当前地图区域 PNG，包含 SDK 绘制的地图、轨迹、围栏和 marker；不包含 Flutter 悬浮按钮、centerPin、分享弹层或卡片文字。
- 可见且宿主活跃、地图已就绪、布局尺寸非零时允许截图。BottomSheet 覆盖不自动令地图不可用；宿主需在请求期间保持地图活跃。
- 本期不新增隐藏地图离屏渲染接口。显式隐藏/后台时不偷偷恢复渲染；返回明确的状态错误。
- 保持 `Future<Uint8List?>`：SDK 无图或超时返回 null；未就绪、已销毁等调用状态错误使用明确 PlatformException。
- 设置双端有限超时（计划 5 秒）；串行处理或明确拒绝并发，保证每次请求只完成一次，销毁时结束挂起请求。
- Android 两个截图回调入口共享完成保护；核实位图所有权，不直接照搬 bitmap.recycle。PNG 编码避免持续阻塞 UI 线程。
- cameraIdle 和 Flutter endOfFrame 不能证明瓦片与原生 marker 已完成。截图流程需要核对 SDK 渲染完成信号，并覆盖弱网、加载中、自定义 pin 位图延迟和相机动画。

### 4. 模拟器探测改名

新增 `AmapNative.shouldUseNativeMap()`，表达当前设备是否允许使用原生地图；Android 内部保留私有 `isEmulator()` 启发式检测；iOS 返回 simulator 环境判断。真实设备仍可能渲染失败，不把结果称为“支持能力”。异常向调用方报告，不通过静默兜底伪造检测结果。

App 负责决定是否规避 Android 模拟器；保持目前 iOS 路径，不因新增 iOS simulator 识别而改变页面策略。检测通过平台接口层转发，便于替换和测试。

`isMapRendererSupported` 尚未存在于主插件当前源码，无须在主插件新增一层旧别名；App 接回主插件时一起替换所有调用点和测试桩。若基线核查发现已发布版本包含旧接口，再增加有期限的 deprecated 兼容转发。

### 5. zoomControlsEnabled 双端通用

使用插件 Flutter 层的统一加减控件调用 zoomBy；Android 原生缩放按钮关闭，避免出现两组按钮。false 时隐藏插件控件，缩放手势独立保留。支持运行中切换和无障碍语义。

保留现有默认 true；这意味着 iOS 将增加默认按钮，属于可见行为变化，需要在变更日志中说明，并逐页检查 App。寻宠页的 false 继续生效。Flutter 控件不进入原生地图 PNG。

### 6. pin 默认颜色不新增对外配置；接受 consumer R8 规则

将用户“pin 默认颜色不对外”落实为：降级针使用内部中性灰默认值，不新增 defaultPinColor/theme 等公开配置，不携带宠物安全状态语义。App 的自定义 Widget 继续负责业务样式。现有 AmapMapPin.pinColor 已是公开字段，本次不删除，避免无关 API 破坏。

consumer R8 规则随插件提供，责任属于引入高德依赖的一方。以实际 SDK 版本为基准复核必要 keep/dontwarn，SDK 升级同步检查。不原样复制宿主 AGP/Kotlin 降级，也不盲目删除反射/JNI 保留规则。在线事故注释转成简短理由和版本依据；是否缩小 keep 范围以 release 证据为准。

### 7. 允许按职责新增原生文件

优先独立生命周期协调器、原生视图适配器和截图请求管理。覆盖物/标记渲染仅在本轮改动确有需要时拆分，不进行全文件形式重构。

ActivityAware 对接生命周期时先核查当前 Flutter embedding 的生命周期接口；无论选用 Lifecycle observer 还是 Application 回调，都必须处理初始状态、配置变更、解绑重绑和多实例，不能复用 App 副本的单一 mapResumed 作为全部状态。

## 三、实施顺序与门禁

公共 API 和状态机在迁移前确定，不再先复制实现、最后清理耦合。

| 阶段 | 内容 | 完成条件 |
|---|---|---|
| 0 基线 | 读取适用规则，记录 Git/依赖版本，按 App Git 历史核对完整差异，保存当前测试结果 | 现有失败与新引入失败可区分；脏文件已记录 |
| 1 生命周期与视图稳定 | 状态机、TextureView 默认、PlatformView 身份稳定、安全释放 | 隐藏→后台→前台仍隐藏；多实例互不影响；键盘和出入页面无闪烁/ANR |
| 2 状态与覆盖物 | 动态定位、当前状态优先于 creationParams 重放、相机不回跳、pin release 位图与标签、围栏精度/虚线 | late mapLoaded 不覆盖最新状态；覆盖物变动不重建地图；双端视觉核验 |
| 3 截图和通用控制 | 截图请求管理、zoomBy、统一缩放控件、isEmulator 和平台接口测试 | 截图 PNG 完整；超时/并发/销毁可收敛；按钮双端一致 |
| 4 发布构建 | consumer R8，独立 example 宿主，构建工具兼容性核查 | Android release 地图/定位/搜索可用，规则影响有记录 |
| 5 App 回接 | 更新版本/路径、移除副本依赖覆盖、改名与测试桩、调整依赖 guard | App 所有地图页面通过；暂不删除副本，保留快速回退 |
| 6 文档与收口 | README、CHANGELOG、示例、版本边界、包内容检查 | 最终 diff 范围清楚；发布/推送另按用户指令执行 |

每个实现提交同时携带对应测试和必要文档，不把测试全部推迟到尾部。每阶段结果写回本方案的执行记录后再推进。

基线需保留主仓库已有 example/ios/Podfile.lock、example/lib/main.dart、example/test/widget_test.dart 修改。App 的 scripts/upload_ipa.sh 未跟踪文件与本任务无关。

## 四、验证清单

- 插件根目录运行格式检查、分析和测试；example 是独立 Flutter 包，其分析与测试在 example/ 内单独运行，基线实测结果以当轮为准。
- App 回接时按其 AGENTS.md 使用 dart analyze lib test，并运行定位、围栏、寻宠、轨迹分享和依赖 guard 的相关测试。
- 原生生命周期验证涵盖可见性/前后台的交叉顺序、配置变更、解绑重绑、多个地图和反复 dispose。
- 覆盖 keyboard、Tab 保活、push/pop、pin 从无到有、图片异步更新、地图加载晚于 moveCamera 的场景。
- Android 真机 release/R8 和 iOS 真机分别核验截图完整性、UI、内存释放及恢复行为；模拟器主要验证检测和页面降级，不自动强行创建被规避的地图。
- 源码字符串 guard 只证明结构存在，不能代替生命周期或截图行为测试；App 现有相关测试需审查后移植有价值的断言。
- 任一真机环节无法执行则记录未验收，不将静态检查描述为端到端通过。

## 五、范围与回滚

采用局部重构迁移，不整体重写。新增职责文件不改变业务职责边界；插件不负责宠物状态色、相机业务取景、分享卡片、微信分享或设备定位流编排。

App 改用主插件与插件实现是两个可回退阶段。回滚通过明确提交或恢复依赖引用，不覆盖用户工作区。生命周期与 TextureView 是有关联的一组修改，不能承诺每个文件都能独立回滚。R8 失败应修复/撤回尚未发布的候选版本，不能带着已知 release 崩溃发布。

## 六、参考资料

- [高德 TextureMapView](https://a.amap.com/lbs/static/unzip/Android_Map_Doc/3D/com/amap/api/maps/TextureMapView.html)
- [Flutter Android Platform Views](https://docs.flutter.dev/platform-integration/android/platform-views)
- [Flutter iOS Platform Views](https://docs.flutter.dev/platform-integration/ios/platform-views)
- [高德 Android AMap 截图接口](https://a.amap.com/lbs/static/unzip/Android_Map_Doc/3D/com/amap/api/maps/AMap.html)

在线说明用于设计依据，实施时仍以当前锁定 SDK 头文件/公开 API 和实际行为核验为准。

## 七、执行记录

2026-09-11：完成 App 使用方式和关键 Git 历史复核，更新上述决策。迁入第一轮通用实现：TextureMapView、生命周期/销毁、动态定位与可见性、zoomBy、takeSnapshot、pin release 修复、围栏相关实现和 consumer R8 规则；保留主插件 AGP/Kotlin 版本，并将渲染策略接口改为 shouldUseNativeMap。修正 Android hostActive/requestedVisible 状态分离。已通过 git diff --check；Flutter/Dart 命令受 SDK 缓存写权限限制，尚未完成构建、测试或真机验证。App 调用点尚未切换。
