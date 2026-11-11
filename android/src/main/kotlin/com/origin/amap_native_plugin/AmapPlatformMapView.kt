package com.origin.amap_native_plugin

import android.content.Context
import android.os.Bundle
import android.view.View
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.model.CameraPosition
import com.amap.api.maps.model.LatLng
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.platform.PlatformView

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
    private val overlays = AmapOverlayController(context, map)
    private val snapshots = AmapSnapshotController(map)
    private var mapLoaded = false
    private val channel = MethodChannel(binaryMessenger, "amap_native_plugin/map_view_$viewId")
    private var currentParams = creationParams
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
                mapLoaded = true
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
        snapshots.dispose()
        channel.setMethodCallHandler(null)
        mapView.removeCallbacks(applyCreationParamsRunnable)
        map.setOnCameraChangeListener(null)
        map.setOnMapClickListener(null)
        map.setOnMapLoadedListener(null)
        map.isMyLocationEnabled = false
        overlays.clearAllOverlays()
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
            snapshots.cancelPending()
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
                overlays.updateMovingPins(args?.get("updates") as? List<*>)
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
            "takeSnapshot" -> snapshots.capture(
                result,
                ready = mapLoaded && mapResumed && hostActive && requestedVisible &&
                    mapView.isAttachedToWindow && mapView.isShown &&
                    mapView.windowVisibility == View.VISIBLE && mapView.width > 0 && mapView.height > 0
            )
            else -> result.notImplemented()
        }
    }

    private fun fitAllOverlays(paddingDp: Float) {
        val bounds = overlays.bounds() ?: return
        val density = mapView.resources.displayMetrics.density
        val paddingPx = (paddingDp * density).toInt()
        map.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, paddingPx))
        cameraOwnedByHost = true
    }

    // Map-load callbacks replay creation parameters, so remember the host's latest camera.
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
        overlays.clearAllOverlays()
        map.uiSettings.isZoomControlsEnabled =
            params?.get("zoomControlsEnabled") as? Boolean ?: true
        val showMyLocation = params?.get("showMyLocation") as? Boolean ?: false
        map.isMyLocationEnabled = showMyLocation
        updateVisibility(params?.get("visible") as? Boolean ?: true)
        overlays.drawCircleGeofences(params?.get("circleGeofences") as? List<*>)
        overlays.drawPins(params?.get("pins") as? List<*>)
        overlays.drawPolylines(params?.get("polylines") as? List<*>)

        if (cameraOwnedByHost) {
            return
        }
        val center = params?.get("initialCenter") as? Map<*, *> ?: return
        val latitude = (center["latitude"] as? Number)?.toDouble() ?: return
        val longitude = (center["longitude"] as? Number)?.toDouble() ?: return
        val zoom = (params["initialZoom"] as? Number)?.toFloat() ?: 15f

        map.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(latitude, longitude), zoom))
    }

    // Map-load callbacks must retain runtime changes rather than replay initial visibility.
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
        overlays.removeCircleOverlays()
        overlays.drawCircleGeofences(geofences)
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["circleGeofences"] = geofences
        currentParams = updatedParams
    }

    private fun updatePins(pins: List<*>?) {
        overlays.removePinMarkers()
        overlays.drawPins(pins)
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["pins"] = pins
        currentParams = updatedParams
    }

    private fun updatePolylines(polylines: List<*>?) {
        overlays.removeRoutePolylines()
        overlays.drawPolylines(polylines)
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["polylines"] = polylines
        currentParams = updatedParams
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

}
