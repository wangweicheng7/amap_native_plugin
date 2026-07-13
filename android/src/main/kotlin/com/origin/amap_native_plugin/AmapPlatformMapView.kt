package com.origin.amap_native_plugin

import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.view.View
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.model.CameraPosition
import com.amap.api.maps.model.CircleOptions
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.Marker
import com.amap.api.maps.model.MarkerOptions
import com.amap.api.maps.model.PolylineOptions
import com.amap.api.maps.model.Polyline
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
    private val circleOverlays = mutableListOf<com.amap.api.maps.model.Circle>()
    private val borderOverlays = mutableListOf<com.amap.api.maps.model.Polyline>()
    private val pinMarkers = mutableListOf<Marker>()
    private val routePolylines = mutableListOf<Polyline>()

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
        map.setOnMapClickListener { latLng ->
            sendMapTapEvent(latLng)
        }
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
            else -> result.notImplemented()
        }
    }

    private fun applyCreationParams(params: Map<*, *>?) {
        clearAllOverlays()
        val showMyLocation = params?.get("showMyLocation") as? Boolean ?: false
        map.isMyLocationEnabled = showMyLocation
        drawCircleGeofences(params?.get("circleGeofences") as? List<*>)
        drawPins(params?.get("pins") as? List<*>)
        drawPolylines(params?.get("polylines") as? List<*>)

        val center = params?.get("initialCenter") as? Map<*, *> ?: return
        val latitude = (center["latitude"] as? Number)?.toDouble() ?: return
        val longitude = (center["longitude"] as? Number)?.toDouble() ?: return
        val zoom = (params["initialZoom"] as? Number)?.toFloat() ?: 15f

        map.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(latitude, longitude), zoom))
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
            val marker = map.addMarker(
                MarkerOptions()
                    .position(LatLng(latitude, longitude))
                    .title(pin["title"] as? String)
                    .snippet(pin["snippet"] as? String)
                    .draggable(pin["draggable"] as? Boolean ?: false)
            ) ?: return@forEach
            pinMarkers.add(marker)
        }
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
        val dashCount = 36
        val pointsPerDash = 5

        for (index in 0 until dashCount step 2) {
            val startFraction = index.toDouble() / dashCount
            val endFraction = (index + 1).toDouble() / dashCount
            val polylinePoints = mutableListOf<LatLng>()

            for (step in 0..pointsPerDash) {
                val fraction = startFraction + (endFraction - startFraction) * (step.toDouble() / pointsPerDash)
                val bearing = 360.0 * fraction
                polylinePoints.add(destinationPoint(center, radiusMeters, bearing))
            }

            borderOverlays.add(
                map.addPolyline(
                PolylineOptions()
                    .addAll(polylinePoints)
                    .color(strokeColor)
                    .width(strokeWidth)
                )
            )
        }
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

    private fun sendMapTapEvent(latLng: LatLng) {
        channel.invokeMethod(
            "mapTap",
            mapOf(
                "latitude" to latLng.latitude,
                "longitude" to latLng.longitude
            )
        )
    }
}
