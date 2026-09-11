package com.origin.amap_native_plugin

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Bundle
import android.view.View
import com.amap.api.maps.AMap
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.TextureMapView
import com.amap.api.maps.model.CameraPosition
import com.amap.api.maps.model.CircleOptions
import com.amap.api.maps.model.BitmapDescriptorFactory
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.LatLngBounds
import com.amap.api.maps.model.Marker
import com.amap.api.maps.model.MarkerOptions
import com.amap.api.maps.model.PolylineOptions
import com.amap.api.maps.model.Polyline
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.platform.PlatformView
import kotlin.math.ceil
import kotlin.math.max

private interface NativeMapView {
    val view: View
    val map: AMap
    fun onCreate(bundle: Bundle)
    fun onResume()
    fun onPause()
    fun onDestroy()
}

private class SurfaceNativeMapView(context: Context) : NativeMapView {
    private val mapView = MapView(context)
    override val view: View = mapView
    override val map: AMap = mapView.map
    override fun onCreate(bundle: Bundle) = mapView.onCreate(bundle)
    override fun onResume() = mapView.onResume()
    override fun onPause() = mapView.onPause()
    override fun onDestroy() = mapView.onDestroy()
}

private class TextureNativeMapView(context: Context) : NativeMapView {
    private val mapView = TextureMapView(context)
    override val view: View = mapView
    override val map: AMap = mapView.map
    override fun onCreate(bundle: Bundle) = mapView.onCreate(bundle)
    override fun onResume() = mapView.onResume()
    override fun onPause() = mapView.onPause()
    override fun onDestroy() = mapView.onDestroy()
}

class AmapPlatformMapView(
    context: Context,
    binaryMessenger: BinaryMessenger,
    viewId: Int,
    creationParams: Map<*, *>?,
    private val onDisposed: (AmapPlatformMapView) -> Unit = {}
) : PlatformView, MethodCallHandler {
    private val nativeMapView: NativeMapView =
        if (creationParams?.get("useTextureView") as? Boolean == true) {
            TextureNativeMapView(context)
        } else {
            SurfaceNativeMapView(context)
        }
    private val mapView = nativeMapView.view
    private val map = nativeMapView.map
    private val channel = MethodChannel(binaryMessenger, "amap_native_plugin/map_view_$viewId")
    private var currentParams = creationParams
    private val circleOverlays = mutableListOf<com.amap.api.maps.model.Circle>()
    private val borderOverlays = mutableListOf<com.amap.api.maps.model.Polyline>()
    private val pinMarkers = mutableListOf<Marker>()
    private val pinIconBitmaps = mutableListOf<Bitmap>()
    private val routePolylines = mutableListOf<Polyline>()
    private var disposed = false

    /// GL 生命周期状态位：onPause/onResume 严格配对、不重复、不遗漏。
    /// init 里首次 onResume 后为 true；dispose 时凭它决定是否补一次 onPause。
    private var mapResumed = false
    private var hostActive = true
    private var requestedVisible = true

    private val applyCreationParamsRunnable = Runnable {
        if (!disposed) {
            applyCreationParams(currentParams)
        }
    }

    /// 宿主（Dart 侧）是否已经按覆盖物范围定过相机。见 [rememberHostCamera]。
    private var cameraOwnedByHost = false

    init {
        channel.setMethodCallHandler(this)
        nativeMapView.onCreate(Bundle())
        nativeMapView.onResume()
        mapResumed = true
        map.setOnCameraChangeListener(object : com.amap.api.maps.AMap.OnCameraChangeListener {
            override fun onCameraChange(cameraPosition: CameraPosition?) {
                sendCameraEvent("cameraMove", cameraPosition?.target)
            }

            override fun onCameraChangeFinish(cameraPosition: CameraPosition?) {
                sendCameraEvent("cameraIdle", cameraPosition?.target)
            }
        })
        map.setOnMapClickListener { latLng ->
            sendMapTapEvent(latLng)
        }
        map.setOnMapLoadedListener {
            if (!disposed) {
                applyCreationParams(currentParams)
            }
        }
        mapView.post(applyCreationParamsRunnable)
    }

    override fun getView(): View = mapView

    override fun dispose() {
        if (disposed) {
            return
        }
        disposed = true
        channel.setMethodCallHandler(null)
        mapView.removeCallbacks(applyCreationParamsRunnable)
        map.setOnCameraChangeListener(null)
        map.setOnMapClickListener(null)
        map.setOnMapLoadedListener(null)
        map.isMyLocationEnabled = false
        clearAllOverlays()
        currentParams = null
        if (mapResumed) {
            mapResumed = false
            nativeMapView.onPause()
        }
        nativeMapView.onDestroy()
        onDisposed(this)
    }

    /// Activity 生命周期桥接（由 Factory 从宿主 Activity 转发）：
    /// 与 updateVisibility 的「暂停渲染」语义同一套状态位，任何路径进来都幂等。
    fun onHostResumed() {
        if (disposed) return
        hostActive = true
        syncRenderState()
    }

    fun onHostPaused() {
        if (disposed) return
        hostActive = false
        syncRenderState()
    }

    private fun syncRenderState() {
        val shouldResume = hostActive && requestedVisible
        if (shouldResume && !mapResumed) {
            mapResumed = true
            nativeMapView.onResume()
        } else if (!shouldResume && mapResumed) {
            mapResumed = false
            nativeMapView.onPause()
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "dispose") {
            dispose()
            result.success(null)
            return
        }
        if (disposed) {
            result.error("map_disposed", "Map view has already been disposed", null)
            return
        }
        when (call.method) {
            "updateMyLocation" -> {
                val args = call.arguments as? Map<*, *>
                updateMyLocation(args?.get("showMyLocation") as? Boolean ?: false)
                result.success(null)
            }
            "setVisible" -> {
                val args = call.arguments as? Map<*, *>
                updateVisibility(args?.get("visible") as? Boolean ?: true)
                result.success(null)
            }
            "updateCircleGeofences" -> {
                val args = call.arguments as? Map<*, *>
                updateCircleGeofences(args?.get("circleGeofences") as? List<*>)
                result.success(null)
            }
            "updatePins" -> {
                val args = call.arguments as? Map<*, *>
                updatePins(args?.get("pins") as? List<*>)
                result.success(null)
            }
            "updatePolylines" -> {
                val args = call.arguments as? Map<*, *>
                updatePolylines(args?.get("polylines") as? List<*>)
                result.success(null)
            }
            "updateMovingPins" -> {
                val args = call.arguments as? Map<*, *>
                updateMovingPins(args?.get("updates") as? List<*>)
                result.success(null)
            }
            "moveCamera" -> {
                val args = call.arguments as? Map<*, *>
                val center = args?.get("center") as? Map<*, *>
                val latitude = (center?.get("latitude") as? Number)?.toDouble()
                val longitude = (center?.get("longitude") as? Number)?.toDouble()
                val zoom = (args?.get("zoom") as? Number)?.toFloat()
                if (latitude == null || longitude == null || zoom == null) {
                    result.error("invalid_arguments", "center and zoom are required", null)
                    return
                }
                map.animateCamera(
                    CameraUpdateFactory.newLatLngZoom(LatLng(latitude, longitude), zoom)
                )
                rememberHostCamera(latitude, longitude, zoom)
                result.success(null)
            }
            "zoomBy" -> {
                val args = call.arguments as? Map<*, *>
                val amount = (args?.get("amount") as? Number)?.toFloat()
                if (amount == null) {
                    result.error("invalid_arguments", "amount is required", null)
                    return
                }
                map.animateCamera(CameraUpdateFactory.zoomBy(amount))
                result.success(null)
            }
            "fitAllOverlays" -> {
                val args = call.arguments as? Map<*, *>
                val paddingDp = (args?.get("padding") as? Number)?.toFloat() ?: 48f
                fitAllOverlays(paddingDp)
                result.success(null)
            }
            "takeSnapshot" -> {
                map.getMapScreenShot(object : com.amap.api.maps.AMap.OnMapScreenShotListener {
                    override fun onMapScreenShot(bitmap: Bitmap?) {
                        if (bitmap == null) {
                            result.success(null)
                            return
                        }
                        val stream = java.io.ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        result.success(stream.toByteArray())
                        bitmap.recycle()
                    }

                    override fun onMapScreenShot(bitmap: Bitmap?, status: Int) {
                        onMapScreenShot(bitmap)
                    }
                })
            }
            else -> result.notImplemented()
        }
    }

    private fun fitAllOverlays(paddingDp: Float) {
        val boundsBuilder = LatLngBounds.Builder()
        var hasPosition = false

        pinMarkers.forEach { marker ->
            boundsBuilder.include(marker.position)
            hasPosition = true
        }
        circleOverlays.forEach { circle ->
            val center = circle.center
            val radius = circle.radius
            listOf(0.0, 90.0, 180.0, 270.0).forEach { bearing ->
                boundsBuilder.include(destinationPoint(center, radius, bearing))
            }
            hasPosition = true
        }
        routePolylines.forEach { polyline ->
            polyline.points.forEach(boundsBuilder::include)
            hasPosition = hasPosition || polyline.points.isNotEmpty()
        }

        if (!hasPosition) {
            return
        }
        val density = mapView.resources.displayMetrics.density
        val paddingPx = (paddingDp * density).toInt()
        map.animateCamera(CameraUpdateFactory.newLatLngBounds(boundsBuilder.build(), paddingPx))
        // 相机已由宿主按覆盖物范围定过，创建参数里的 initialCenter 从此作废（理由见
        // rememberHostCamera）。这一程无法用一个中心点复现，所以只关掉重放那一步。
        cameraOwnedByHost = true
    }

    /// moveCamera 必须把落点写回 currentParams —— 否则 onMapLoaded / mapView.post
    /// 上的**重放**会拿创建那一刻的 initialCenter 把相机拽回去。
    ///
    /// 症状：「设定安全区」页的落点已经移到手机/宠物位置，地图瓦片加载完成的瞬间
    /// 又跳回写死的默认坐标（天安门），且随后的 onCameraChange 会把那个坐标当成
    /// 「用户选的中心」回灌进业务状态 —— 用户看到的就是「安全区默认在北京」。
    /// 重放本身有存在意义（地图就绪前应用的参数会丢），要改的是它重放**陈旧**坐标。
    ///
    /// 约定同本文件其余 update*：谁改了状态谁写回 currentParams（见 updateMyLocation
    /// 的注释，那是同一个坑在蓝点上的第一次）。
    private fun rememberHostCamera(latitude: Double, longitude: Double, zoom: Float) {
        cameraOwnedByHost = false
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["initialCenter"] = mapOf("latitude" to latitude, "longitude" to longitude)
        updatedParams["initialZoom"] = zoom
        currentParams = updatedParams
    }

    private fun applyCreationParams(params: Map<*, *>?) {
        clearAllOverlays()
        map.uiSettings.isZoomControlsEnabled =
            params?.get("zoomControlsEnabled") as? Boolean ?: true
        val showMyLocation = params?.get("showMyLocation") as? Boolean ?: false
        map.isMyLocationEnabled = showMyLocation
        updateVisibility(params?.get("visible") as? Boolean ?: true)
        drawCircleGeofences(params?.get("circleGeofences") as? List<*>)
        drawPins(params?.get("pins") as? List<*>)
        drawPolylines(params?.get("polylines") as? List<*>)

        if (cameraOwnedByHost) {
            return
        }
        val center = params?.get("initialCenter") as? Map<*, *> ?: return
        val latitude = (center["latitude"] as? Number)?.toDouble() ?: return
        val longitude = (center["longitude"] as? Number)?.toDouble() ?: return
        val zoom = (params["initialZoom"] as? Number)?.toFloat() ?: 15f

        map.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(latitude, longitude), zoom))
    }

    /// 必须同步写回 currentParams：onMapLoaded 与 mapView.post 都会拿它**重放**一次
    /// applyCreationParams（地图瓦片加载完可能在本次更新之后才发生）。只设
    /// isMyLocationEnabled 而不写回，蓝点会在地图加载完成的瞬间按创建时的旧值复活 ——
    /// 与本方法要修的缺陷一模一样，只是延迟了几秒。同文件其余 update* 皆循此约定。
    private fun updateMyLocation(showMyLocation: Boolean) {
        map.isMyLocationEnabled = showMyLocation
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["showMyLocation"] = showMyLocation
        currentParams = updatedParams
    }

    /// 切 Tab 时「暂停渲染」而非「销毁 Surface」：不调 View.GONE/INVISIBLE，
    /// 避免 SurfaceView 销毁 GL Surface 触发重建竞态（SIGABRT）。隐藏语义改为
    /// onPause/onResume 配对 —— GPU 在 onPause 后由 SurfaceView 自动停止绘制。
    private fun updateVisibility(visible: Boolean) {
        requestedVisible = visible
        syncRenderState()
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["visible"] = visible
        currentParams = updatedParams
    }

    private fun updateCircleGeofences(geofences: List<*>?) {
        removeCircleOverlays()
        drawCircleGeofences(geofences)
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["circleGeofences"] = geofences
        currentParams = updatedParams
    }

    private fun updatePins(pins: List<*>?) {
        removePinMarkers()
        drawPins(pins)
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["pins"] = pins
        currentParams = updatedParams
    }

    private fun updatePolylines(polylines: List<*>?) {
        removeRoutePolylines()
        drawPolylines(polylines)
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["polylines"] = polylines
        currentParams = updatedParams
    }

    private fun updateMovingPins(updates: List<*>?) {
        updates?.forEach { item ->
            val update = item as? Map<*, *> ?: return@forEach
            val index = (update["index"] as? Number)?.toInt() ?: return@forEach
            val position = update["position"] as? Map<*, *> ?: return@forEach
            val latitude = (position["latitude"] as? Number)?.toDouble() ?: return@forEach
            val longitude = (position["longitude"] as? Number)?.toDouble() ?: return@forEach
            pinMarkers.getOrNull(index)?.position = LatLng(latitude, longitude)
        }
    }

    private fun drawCircleGeofences(geofences: List<*>?) {
        geofences?.forEach { item ->
            val geofence = item as? Map<*, *> ?: return@forEach
            val center = geofence["center"] as? Map<*, *> ?: return@forEach
            val latitude = (center["latitude"] as? Number)?.toDouble() ?: return@forEach
            val longitude = (center["longitude"] as? Number)?.toDouble() ?: return@forEach
            val radius = (geofence["radiusMeters"] as? Number)?.toDouble() ?: return@forEach
            val strokeColor = (geofence["strokeColor"] as? Number)?.toInt() ?: (0xFF2563EB).toInt()
            val fillColor = (geofence["fillColor"] as? Number)?.toInt() ?: 0x332563EB
            val strokeWidth = (geofence["strokeWidth"] as? Number)?.toFloat() ?: 2f

            circleOverlays.add(
                map.addCircle(
                    CircleOptions()
                        .center(LatLng(latitude, longitude))
                        .radius(radius)
                        .strokeColor(Color.TRANSPARENT)
                        .fillColor(fillColor)
                        .strokeWidth(0f)
                )
            )

            drawDashedCircleBorder(
                center = LatLng(latitude, longitude),
                radiusMeters = radius,
                strokeColor = strokeColor,
                strokeWidth = strokeWidth
            )
        }
    }

    private fun drawPins(pins: List<*>?) {
        pins?.forEach { item ->
            val pin = item as? Map<*, *> ?: return@forEach
            val position = pin["position"] as? Map<*, *> ?: return@forEach
            val latitude = (position["latitude"] as? Number)?.toDouble() ?: return@forEach
            val longitude = (position["longitude"] as? Number)?.toDouble() ?: return@forEach
            val options = MarkerOptions()
                .position(LatLng(latitude, longitude))
                .title(pin["title"] as? String)
                .snippet(pin["snippet"] as? String)
                .draggable(pin["draggable"] as? Boolean ?: false)
            val label = (pin["label"] as? String)?.takeIf { it.isNotBlank() }
            val imageBitmap = (pin["imageBytes"] as? ByteArray)
                ?.takeIf { it.isNotEmpty() }
                ?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                ?: (pin["imageAsset"] as? String)
                    ?.takeIf { it.isNotBlank() }
                    ?.let(::loadFlutterAssetBitmap)
            var customIconBitmap: Bitmap? = null
            if (label != null || imageBitmap != null) {
                val customIcon = createCustomPinBitmap(
                    label = label,
                    imageBitmap = imageBitmap,
                    imageWidthDp = (pin["imageWidth"] as? Number)?.toFloat() ?: 44f,
                    imageHeightDp = (pin["imageHeight"] as? Number)?.toFloat() ?: 44f,
                    // 中性灰兜底：降级针不得落进宿主应用的状态色板（绿/琥珀/红）
                    pinColor = (pin["pinColor"] as? Number)?.toInt() ?: 0xFF9E9E9E.toInt(),
                    textColor = (pin["labelTextColor"] as? Number)?.toInt() ?: Color.WHITE,
                    backgroundColor = (pin["labelBackgroundColor"] as? Number)?.toInt()
                        ?: 0xE62D3748.toInt(),
                    labelTextScaleFactor = (pin["labelTextScaleFactor"] as? Number)?.toFloat()
                        ?: 1f
                )
                customIconBitmap = customIcon.bitmap
                options.icon(BitmapDescriptorFactory.fromBitmap(customIcon.bitmap))
                options.anchor(customIcon.anchorX, 1f)
            }
            val marker = try {
                map.addMarker(options)
            } finally {
                // 合成后源图已经无用；Marker 图标本体则保留到 removePinMarkers，兼容
                // 不同高德 SDK 版本对 fromBitmap 是否同步复制像素的实现差异。
                imageBitmap?.takeUnless(Bitmap::isRecycled)?.recycle()
            }
            if (marker == null) {
                customIconBitmap?.takeUnless(Bitmap::isRecycled)?.recycle()
                return@forEach
            }
            pinMarkers.add(marker)
            customIconBitmap?.let(pinIconBitmaps::add)
        }
    }

    private fun loadFlutterAssetBitmap(assetName: String): Bitmap? {
        return runCatching {
            val assetKey = FlutterInjector.instance()
                .flutterLoader()
                .getLookupKeyForAsset(assetName)
            mapView.context.assets.open(assetKey).use(BitmapFactory::decodeStream)
        }.getOrNull()
    }

    private fun createCustomPinBitmap(
        label: String?,
        imageBitmap: Bitmap?,
        imageWidthDp: Float,
        imageHeightDp: Float,
        pinColor: Int,
        textColor: Int,
        backgroundColor: Int,
        labelTextScaleFactor: Float
    ): LabeledPinBitmap {
        val density = mapView.resources.displayMetrics.density
        val safeLabelTextScaleFactor = labelTextScaleFactor
            .takeIf { it.isFinite() && it > 0f }
            ?.coerceAtMost(4f)
            ?: 1f
        val pinWidth = (if (imageBitmap == null) 32f else imageWidthDp) * density
        val pinHeight = (if (imageBitmap == null) 42f else imageHeightDp) * density
        val gap = 6f * density
        val labelHeight = 32f * density * safeLabelTextScaleFactor
        val horizontalPadding = 10f * density * safeLabelTextScaleFactor
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColor
            textSize = 14f * density * safeLabelTextScaleFactor
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        val labelWidth = label?.let { textPaint.measureText(it) + horizontalPadding * 2 } ?: 0f
        val bitmapWidth = ceil(pinWidth + if (label == null) 0f else gap + labelWidth).toInt()
        val bitmapHeight = ceil(max(pinHeight, labelHeight)).toInt()
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        if (imageBitmap != null) {
            // 默认标签高 32dp，而「我的位置」圆点只有 22dp。若一律从 y=0 画，
            // 两者只是顶边对齐，视觉中心会相差 5dp。短图标在合成画布内垂直居中，
            // 宠物针等高于标签的图标仍保持 y=0，既有落点不变。
            val pinTop = (bitmapHeight - pinHeight).coerceAtLeast(0f) / 2f
            canvas.drawBitmap(
                imageBitmap,
                null,
                RectF(0f, pinTop, pinWidth, pinTop + pinHeight),
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            )
        } else {
            val pinPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = pinColor }
            val triangle = Path().apply {
                moveTo(8f * density, 21f * density)
                lineTo(pinWidth / 2f, pinHeight)
                lineTo(24f * density, 21f * density)
                close()
            }
            canvas.drawPath(triangle, pinPaint)
            canvas.drawCircle(pinWidth / 2f, 14f * density, 12f * density, pinPaint)
            canvas.drawCircle(
                pinWidth / 2f,
                14f * density,
                4f * density,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
            )
        }

        if (label != null) {
            val labelLeft = pinWidth + gap
            val labelTop = (bitmapHeight - labelHeight) / 2f
            val labelRect = RectF(labelLeft, labelTop, labelLeft + labelWidth, labelTop + labelHeight)
            canvas.drawRoundRect(
                labelRect,
                8f * density,
                8f * density,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = backgroundColor }
            )
            val baseline = labelRect.centerY() - (textPaint.ascent() + textPaint.descent()) / 2f
            canvas.drawText(label, labelLeft + horizontalPadding, baseline, textPaint)
        }

        return LabeledPinBitmap(bitmap, (pinWidth / 2f) / bitmapWidth.toFloat())
    }

    private fun drawPolylines(polylines: List<*>?) {
        polylines?.forEach { item ->
            val polyline = item as? Map<*, *> ?: return@forEach
            val points = (polyline["points"] as? List<*>)
                ?.mapNotNull { point ->
                    val coordinate = point as? Map<*, *> ?: return@mapNotNull null
                    val latitude = (coordinate["latitude"] as? Number)?.toDouble()
                        ?: return@mapNotNull null
                    val longitude = (coordinate["longitude"] as? Number)?.toDouble()
                        ?: return@mapNotNull null
                    LatLng(latitude, longitude)
                }
                ?: return@forEach
            if (points.size < 2) {
                return@forEach
            }

            routePolylines.add(
                map.addPolyline(
                    PolylineOptions()
                        .addAll(points)
                        .color((polyline["color"] as? Number)?.toInt() ?: (0xFFFF5B00).toInt())
                        .width((polyline["width"] as? Number)?.toFloat() ?: 6f)
                )
            )
        }
    }

    private fun drawDashedCircleBorder(
        center: LatLng,
        radiusMeters: Double,
        strokeColor: Int,
        strokeWidth: Float
    ) {
        // 分段透明色复刻 iOS 的 10° 实线弧 / 10° 空白，同时避免把一个围栏
        // 拆成 18 个原生覆盖物。必须关闭高德的折线点抽稀，否则圆周会再次出现折角。
        val circlePoints = (0..CIRCLE_SEGMENT_COUNT).map { segment ->
            val bearing = 360.0 * segment / CIRCLE_SEGMENT_COUNT
            destinationPoint(center, radiusMeters, bearing)
        }
        val circleColors = (0..CIRCLE_SEGMENT_COUNT).map { segment ->
            val dashIndex = segment / CIRCLE_SEGMENTS_PER_DASH
            if (dashIndex % 2 == 0) strokeColor else Color.TRANSPARENT
        }
        val borderOptions = PolylineOptions()
            .addAll(circlePoints)
            .colorValues(circleColors)
            .useGradient(false)
            .width(strokeWidth)
        borderOptions.setReducePoint(false)
        borderOverlays.add(
            map.addPolyline(borderOptions)
        )
    }

    private fun removeCircleOverlays() {
        circleOverlays.forEach { it.remove() }
        circleOverlays.clear()
        borderOverlays.forEach { it.remove() }
        borderOverlays.clear()
    }

    private fun removePinMarkers() {
        pinMarkers.forEach { it.remove() }
        pinMarkers.clear()
        // Flutter 针图片会被合成成 Android Bitmap。只 remove Marker 不会替宿主回收
        // 这些 Bitmap，反复进入轨迹收藏详情会持续推高 native heap，直至白屏/OOM。
        pinIconBitmaps.forEach { bitmap ->
            bitmap.takeUnless(Bitmap::isRecycled)?.recycle()
        }
        pinIconBitmaps.clear()
    }

    private fun removeRoutePolylines() {
        routePolylines.forEach { it.remove() }
        routePolylines.clear()
    }

    private fun clearAllOverlays() {
        removeCircleOverlays()
        removePinMarkers()
        removeRoutePolylines()
    }

    private fun destinationPoint(center: LatLng, radiusMeters: Double, bearingDegrees: Double): LatLng {
        val earthRadiusMeters = 6_378_137.0
        val angularDistance = radiusMeters / earthRadiusMeters
        val bearing = Math.toRadians(bearingDegrees)
        val latitude1 = Math.toRadians(center.latitude)
        val longitude1 = Math.toRadians(center.longitude)

        val sinLatitude1 = kotlin.math.sin(latitude1)
        val cosLatitude1 = kotlin.math.cos(latitude1)
        val sinAngularDistance = kotlin.math.sin(angularDistance)
        val cosAngularDistance = kotlin.math.cos(angularDistance)

        val latitude2 = kotlin.math.asin(
            sinLatitude1 * cosAngularDistance +
                cosLatitude1 * sinAngularDistance * kotlin.math.cos(bearing)
        )
        val longitude2 = longitude1 + kotlin.math.atan2(
            kotlin.math.sin(bearing) * sinAngularDistance * cosLatitude1,
            cosAngularDistance - sinLatitude1 * kotlin.math.sin(latitude2)
        )

        return LatLng(
            Math.toDegrees(latitude2),
            normalizeLongitude(Math.toDegrees(longitude2))
        )
    }

    private fun normalizeLongitude(longitude: Double): Double {
        var normalized = longitude
        while (normalized < -180.0) {
            normalized += 360.0
        }
        while (normalized > 180.0) {
            normalized -= 360.0
        }
        return normalized
    }

    private fun sendCameraEvent(method: String, center: LatLng?) {
        if (disposed || center == null) {
            return
        }

        channel.invokeMethod(
            method,
            mapOf(
                "latitude" to center.latitude,
                "longitude" to center.longitude
            )
        )
    }

    private fun sendMapTapEvent(latLng: LatLng) {
        if (disposed) {
            return
        }
        channel.invokeMethod(
            "mapTap",
            mapOf(
                "latitude" to latLng.latitude,
                "longitude" to latLng.longitude
            )
        )
    }

    private companion object {
        // 2° 一段以避免大半径围栏出现明显折线，仍只生成一个原生覆盖物。
        const val CIRCLE_SEGMENT_COUNT = 180
        const val CIRCLE_SEGMENTS_PER_DASH = 5
    }
}

private data class LabeledPinBitmap(
    val bitmap: Bitmap,
    val anchorX: Float
)
