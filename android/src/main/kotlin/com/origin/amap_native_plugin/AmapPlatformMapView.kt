package com.origin.amap_native_plugin

import android.content.Context
import android.os.Bundle
import android.view.View
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.model.CameraPosition
import com.amap.api.maps.model.CircleOptions
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
    creationParams: Map<*, *>?
) : PlatformView, MethodCallHandler {
    private val mapView = MapView(context)
    private val map = mapView.map
    private val channel = MethodChannel(binaryMessenger, "amap_native_plugin/map_view_$viewId")
    private var currentParams = creationParams

    init {
        channel.setMethodCallHandler(this)
        mapView.onCreate(Bundle())
        mapView.onResume()
        map.setOnCameraChangeListener(object : com.amap.api.maps.AMap.OnCameraChangeListener {
            override fun onCameraChange(cameraPosition: CameraPosition?) {
                sendCameraEvent("cameraMove", cameraPosition?.target)
            }

            override fun onCameraChangeFinish(cameraPosition: CameraPosition?) {
                sendCameraEvent("cameraIdle", cameraPosition?.target)
            }
        })
        map.setOnMapLoadedListener {
            applyCreationParams(currentParams)
        }
        mapView.post {
            applyCreationParams(currentParams)
        }
    }

    override fun getView(): View = mapView

    override fun dispose() {
        channel.setMethodCallHandler(null)
        mapView.onPause()
        mapView.onDestroy()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "updateCircleGeofences" -> {
                val args = call.arguments as? Map<*, *>
                updateCircleGeofences(args?.get("circleGeofences") as? List<*>)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun applyCreationParams(params: Map<*, *>?) {
        map.clear()
        val showMyLocation = params?.get("showMyLocation") as? Boolean ?: false
        map.isMyLocationEnabled = showMyLocation
        drawCircleGeofences(params?.get("circleGeofences") as? List<*>)

        val center = params?.get("initialCenter") as? Map<*, *> ?: return
        val latitude = (center["latitude"] as? Number)?.toDouble() ?: return
        val longitude = (center["longitude"] as? Number)?.toDouble() ?: return
        val zoom = (params["initialZoom"] as? Number)?.toFloat() ?: 15f

        map.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(latitude, longitude), zoom))
    }

    private fun updateCircleGeofences(geofences: List<*>?) {
        map.clear()
        drawCircleGeofences(geofences)
        val updatedParams = currentParams
            ?.entries
            ?.associate { it.key to it.value }
            ?.toMutableMap()
            ?: mutableMapOf<Any?, Any?>()
        updatedParams["circleGeofences"] = geofences
        currentParams = updatedParams
    }

    private fun drawCircleGeofences(geofences: List<*>?) {
        geofences?.forEach { item ->
            val geofence = item as? Map<*, *> ?: return@forEach
            val center = geofence["center"] as? Map<*, *> ?: return@forEach
            val latitude = (center["latitude"] as? Number)?.toDouble() ?: return@forEach
            val longitude = (center["longitude"] as? Number)?.toDouble() ?: return@forEach
            val radius = (geofence["radiusMeters"] as? Number)?.toDouble() ?: return@forEach

            map.addCircle(
                CircleOptions()
                    .center(LatLng(latitude, longitude))
                    .radius(radius)
                    .strokeColor((geofence["strokeColor"] as? Number)?.toInt() ?: (0xFF2563EB).toInt())
                    .fillColor((geofence["fillColor"] as? Number)?.toInt() ?: 0x332563EB)
                    .strokeWidth((geofence["strokeWidth"] as? Number)?.toFloat() ?: 2f)
            )
        }
    }

    private fun sendCameraEvent(method: String, center: LatLng?) {
        if (center == null) {
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
}
