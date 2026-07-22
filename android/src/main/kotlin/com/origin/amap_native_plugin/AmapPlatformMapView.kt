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
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
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
        map.setOnCameraChangeListener(null)
        map.setOnMapClickListener(null)
        map.setOnMapLoadedListener(null)
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
                result.success(null)
            }
            "fitAllOverlays" -> {
                val args = call.arguments as? Map<*, *>
                val paddingDp = (args?.get("padding") as? Number)?.toFloat() ?: 48f
                fitAllOverlays(paddingDp)
                result.success(null)
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
            if (label != null || imageBitmap != null) {
                val customIcon = createCustomPinBitmap(
                    label = label,
                    imageBitmap = imageBitmap,
                    imageWidthDp = (pin["imageWidth"] as? Number)?.toFloat() ?: 44f,
                    imageHeightDp = (pin["imageHeight"] as? Number)?.toFloat() ?: 44f,
                    pinColor = (pin["pinColor"] as? Number)?.toInt() ?: 0xFFF97316.toInt(),
                    textColor = (pin["labelTextColor"] as? Number)?.toInt() ?: Color.WHITE,
                    backgroundColor = (pin["labelBackgroundColor"] as? Number)?.toInt()
                        ?: 0xE62D3748.toInt()
                )
                options.icon(BitmapDescriptorFactory.fromBitmap(customIcon.bitmap))
                options.anchor(customIcon.anchorX, 1f)
            }
            val marker = map.addMarker(options) ?: return@forEach
            pinMarkers.add(marker)
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
        backgroundColor: Int
    ): LabeledPinBitmap {
        val density = mapView.resources.displayMetrics.density
        val scaledDensity = mapView.resources.displayMetrics.scaledDensity
        val pinWidth = (if (imageBitmap == null) 32f else imageWidthDp) * density
        val pinHeight = (if (imageBitmap == null) 42f else imageHeightDp) * density
        val gap = 6f * density
        val labelHeight = 32f * density
        val horizontalPadding = 10f * density
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColor
            textSize = 14f * scaledDensity
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        val labelWidth = label?.let { textPaint.measureText(it) + horizontalPadding * 2 } ?: 0f
        val bitmapWidth = ceil(pinWidth + if (label == null) 0f else gap + labelWidth).toInt()
        val bitmapHeight = ceil(max(pinHeight, labelHeight)).toInt()
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        if (imageBitmap != null) {
            canvas.drawBitmap(
                imageBitmap,
                null,
                RectF(0f, 0f, pinWidth, pinHeight),
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
            val labelTop = (pinHeight - labelHeight) / 2f
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

private data class LabeledPinBitmap(
    val bitmap: Bitmap,
    val anchorX: Float
)
