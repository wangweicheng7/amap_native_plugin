package com.origin.amap_native_plugin

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import com.amap.api.maps.AMap
import com.amap.api.maps.model.BitmapDescriptorFactory
import com.amap.api.maps.model.CircleOptions
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.LatLngBounds
import com.amap.api.maps.model.Marker
import com.amap.api.maps.model.MarkerOptions
import com.amap.api.maps.model.Polyline
import com.amap.api.maps.model.PolylineOptions

internal class AmapOverlayController(context: Context, private val map: AMap) {
    private val pinRenderer = AmapPinRenderer(context)
    private val circleOverlays = mutableListOf<com.amap.api.maps.model.Circle>()
    private val borderOverlays = mutableListOf<com.amap.api.maps.model.Polyline>()
    private val pinMarkers = mutableListOf<Marker>()
    private val pinIconBitmaps = mutableListOf<Bitmap>()
    private val routePolylines = mutableListOf<Polyline>()

    fun bounds(): LatLngBounds? {
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

        return if (hasPosition) boundsBuilder.build() else null
    }

    fun updateMovingPins(updates: List<*>?) {
        updates?.forEach { item ->
            val update = item as? Map<*, *> ?: return@forEach
            val index = (update["index"] as? Number)?.toInt() ?: return@forEach
            val position = update["position"] as? Map<*, *> ?: return@forEach
            val latitude = (position["latitude"] as? Number)?.toDouble() ?: return@forEach
            val longitude = (position["longitude"] as? Number)?.toDouble() ?: return@forEach
            pinMarkers.getOrNull(index)?.position = LatLng(latitude, longitude)
        }
    }

    fun drawCircleGeofences(geofences: List<*>?) {
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

    fun drawPins(pins: List<*>?) {
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
                    ?.let(pinRenderer::loadFlutterAssetBitmap)
            var customIconBitmap: Bitmap? = null
            if (label != null || imageBitmap != null) {
                val customIcon = pinRenderer.createCustomPinBitmap(
                    label = label,
                    imageBitmap = imageBitmap,
                    imageWidthDp = (pin["imageWidth"] as? Number)?.toFloat() ?: 44f,
                    imageHeightDp = (pin["imageHeight"] as? Number)?.toFloat() ?: 44f,
                    // Keep the default fallback independent of host application status colors.
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

    fun drawPolylines(polylines: List<*>?) {
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
                        .setDottedLine(polyline["dashed"] as? Boolean ?: false)
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

    fun removeCircleOverlays() {
        circleOverlays.forEach { it.remove() }
        circleOverlays.clear()
        borderOverlays.forEach { it.remove() }
        borderOverlays.clear()
    }

    fun removePinMarkers() {
        pinMarkers.forEach { it.remove() }
        pinMarkers.clear()
        // Removing a marker does not release the composed bitmap owned by this view.
        pinIconBitmaps.forEach { bitmap ->
            bitmap.takeUnless(Bitmap::isRecycled)?.recycle()
        }
        pinIconBitmaps.clear()
    }

    fun removeRoutePolylines() {
        routePolylines.forEach { it.remove() }
        routePolylines.clear()
    }

    fun clearAllOverlays() {
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

    private companion object {
        // 2° 一段以避免大半径围栏出现明显折线，仍只生成一个原生覆盖物。
        const val CIRCLE_SEGMENT_COUNT = 180
        const val CIRCLE_SEGMENTS_PER_DASH = 5
    }
}
