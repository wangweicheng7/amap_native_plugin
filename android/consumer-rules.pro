# 高德组合 SDK（com.amap.api:3dmap-location-search:11.1.200_loc11.1.200_sea9.7.4）R8 保留规则。
#
# ── 为什么规则必须由我们提供 ────────────────────────────────────────────────
# 该依赖以 **jar** 发布（POM packaging=jar，Maven 上根本没有 .aar），jar 内 META-INF 只有
# MANIFEST.MF —— 既没有 aar 的 proguard.txt，也没有 META-INF/proguard/ 下的自动规则。
# 也就是说高德**结构上不可能**自带保留规则，只能由接入方写。
#
# ── 为什么写在插件里而不是 App 层 ──────────────────────────────────────────
# 谁引入依赖谁负责它的保留规则：consumerProguardFiles 会随 library 传播到任何宿主 App，
# 换一个工程接这个插件不必再踩一次。App 层 proguard-rules.pro 只是兜底位置。
#
# ── 为什么只有 release 炸 ──────────────────────────────────────────────────
# Flutter 的 Gradle 插件默认给 release 打开 R8：flutter_tools/gradle 的
# FlutterPluginUtils.shouldShrinkResources() 无 `-Pshrink` 时返回 true，
# FlutterPlugin.kt 随即置 release.isMinifyEnabled = true。debug/profile 不走这条路径，
# 所以同一份代码 profile 正常、release 进定位页即闪退。
#
# ── 本次事故链（2026-08-06，OPPO PHM110 / Android 15，develop 6dc1efe）────────
# 进定位页 → showMyLocation=true → 地图 SDK 取默认 LocationSource →
# com.amap.api.col.3sl.f2（源文件名 AMapReflectionLocationSource.java）**纯反射**加载
# com.amap.api.location.AMapLocationClient / AMapLocationListener /
# AMapLocationClientOption。全 SDK 无任何静态引用指向这几个类，R8 判定未使用并删除
# （见 build/app/outputs/mapping/release/usage.txt）→ 运行时 Class.forName 抛
# ClassNotFoundException → libAMapOpenMapJNI.so（= libAMapSDK_MAP_v11_1_200.so 的 SONAME）
# 拿着 null jclass 调 GetStaticMethodID → JNI FATAL → SIGABRT，崩在 GLSurfaceView$GLThread。
#
# ── 取证方式 ───────────────────────────────────────────────────────────────
# 下列每条规则都对着 11.1.200 这颗 jar 实测过（unzip 清单 + .so 的 JNI 类名字符串 +
# .class 常量池里的反射字符串），不是照抄官方文档。官方文档针对的是分体 SDK 的旧版本，
# 直接抄会漏掉 11.x 的包名迁移（见下方 com.loc / com.amap.location 两条）。

# ── 3D 地图 ────────────────────────────────────────────────────────────────
# libAMapOpenMapJNI.so 内以 JNI 类名字符串直接查找的类共 93 个，全部落在
# com/amap/api/maps/model/**（含 particle、animation、routeoverlay、contourline、
# amap3dmodeltile）与 com/autonavi/base/**（ae/gmap、ae/gmap/glyph、ae/gmap/bean、
# ae/gmap/gloverlay、amap/mapcore）。JNI FindClass/GetMethodID/GetFieldID 全部按名解析，
# R8 改名即失效，所以必须连成员一起保。
-keep class com.amap.api.maps.** { *; }
-keep class com.amap.api.trace.** { *; }
# com.autonavi.** 同时覆盖三类按名解析目标：地图 JNI 回调（com.autonavi.base.**）、
# 反射字符串 com.autonavi.jni.server.aos.ServerkeyNative 与 com.autonavi.server.aos.serverkey
# （鉴权）、以及官方规则单列的 com.autonavi.aps.amapapi.model.**（定位结果模型）。
-keep class com.autonavi.** { *; }

# ── 定位（本次崩溃的直接原因）──────────────────────────────────────────────
# f2 常量池里的反射目标：AMapLocationClient、AMapLocation、AMapLocationListener、
# AMapLocationClientOption、AMapLocationClientOption$AMapLocationMode；方法
# setLocationListener / setLocationOption / startLocation / stopLocation / onDestroy /
# setInterval / setOnceLocation / setLocationMode 一律 getMethod 按名取 —— 因此不能只
# -keepnames，必须连成员保住。
-keep class com.amap.api.location.** { *; }
# 围栏与定位同源：GeoFenceClient 静态引用 AMapLocationClient，官方规则亦同列。
-keep class com.amap.api.fence.** { *; }

# ── 定位内核：11.x 的包名迁移 ──────────────────────────────────────────────
# 官方定位规则里的 com.loc.** 在 11.1.200 已**不存在**（jar 内 com/loc/ 计 0 个 class），
# 等价内核搬到了 com.amap.location.**（913 个 class）。libapssdk.so 以 JNI 类名字符串直接
# 查找 com/amap/location/support/AmapContext、support/bean/gnss/{AmapGnssClock,
# AmapGnssMeasurement,AmapSatellite}、support/bean/location/AmapLocation、support/log/ALLog、
# support/security/gnssrtk/**、signal/impl/util/SystemServerHelper —— 少这条，蓝点这次不崩，
# 下次 GNSS 回调照样崩。
-keep class com.amap.location.** { *; }
# 官方文档原文里的旧包名。本版本 jar 内无匹配类，是一条**空转规则**，零体积代价；
# 留着是为了日后 SDK 降级或换回分体版时规则仍然成立。
-keep class com.loc.** { *; }

# ── 搜索 ───────────────────────────────────────────────────────────────────
# 插件 searchPlaces 用 Inputtips / InputtipsQuery / LatLonPoint / ServiceSettings，
# 回调经 InputtipsListener 按名分发。
-keep class com.amap.api.services.** { *; }

# ── 动态核心 ───────────────────────────────────────────────────────────────
# 反射字符串 com.amap.apis.utils.core.dynamiccore（jar 内 com/amap/apis/ 共 6 个 class）。
-keep class com.amap.apis.** { *; }

# ── 刻意**不**保留 com.amap.api.col.**（818 个 class，占 jar 的大头）────────
# 它是高德自己已经用 R8 混淆过的内部实现（f2.class 里带
# {"compilation-mode":"release","r8-mode":"compatibility"} 标记），全部经公开 API 静态可达，
# 被二次改名不影响运行。jar 里仅有的两处裸串 "com.amap.api.col" / "com.amap.api.collection"
# 出现在 sa.class 的 uncaughtException 旁，是崩溃上报的包名前缀过滤，不是 Class.forName 参数。
# 唯一副作用：高德自家崩溃上报可能认不出被改名的栈帧 —— 与闪退无关。

# ── 缺失的可选依赖：必须显式放行，否则 R8 判**构建失败** ────────────────────
# AGP 8+ 把「被保留的类引用了不存在的类」从警告升级为 error，构建在
# `:app:minifyReleaseWithR8` 直接中断（2026-08-06 实测）。这两个类高德压根没打进 jar
# （实测 jar 内 com/amap/ams/** 与 net/jafama/** 条目数均为 0），是它自己的可选模块：
#
#   com.amap.ams.gnss.GnssSoftLocator ← com.amap.location.fusion.original.a.a.<init>
#   net.jafama.FastMath               ← com.autonavi.aps.protocol...fields.context.b.e()
#
# 关键在于：这是**上面那些 -keep 带出来的**。不保留定位内核时，R8 早把这两个引用方
# 一起当死代码删了，自然也不会去检查它们的引用 —— 所以修复闪退的同时必然要处理这里。
# 而 debug/profile 不跑 R8，同样缺这两个类却一直跑得好好的，说明 SDK 自己能处理它们的
# 缺席；-dontwarn 只是让 release 恢复到与 debug 相同的状态，不是掩盖真问题。
#
# 只放行这两个**具体类**，不用 `-dontwarn com.amap.**` 那种大范围写法：R8 的缺失类分析
# 是整个程序一次算完的，这两个就是全部（已用修正后的常量池扫描独立复核，结论一致）；
# 写宽了会把将来真正的缺失一起吞掉。
-dontwarn com.amap.ams.gnss.GnssSoftLocator
-dontwarn net.jafama.FastMath
