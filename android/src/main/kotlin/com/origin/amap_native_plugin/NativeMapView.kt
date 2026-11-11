package com.origin.amap_native_plugin

import android.content.Context
import android.os.Bundle
import android.view.View
import com.amap.api.maps.AMap
import com.amap.api.maps.MapView
import com.amap.api.maps.TextureMapView

internal interface NativeMapView {
    val view: View
    val map: AMap
    fun onCreate(bundle: Bundle)
    fun onResume()
    fun onPause()
    fun onDestroy()
}

internal class SurfaceNativeMapView(context: Context) : NativeMapView {
    private val mapView = MapView(context)
    override val view: View = mapView
    override val map: AMap = mapView.map
    override fun onCreate(bundle: Bundle) = mapView.onCreate(bundle)
    override fun onResume() = mapView.onResume()
    override fun onPause() = mapView.onPause()
    override fun onDestroy() = mapView.onDestroy()
}

internal class TextureNativeMapView(context: Context) : NativeMapView {
    private val mapView = TextureMapView(context)
    override val view: View = mapView
    override val map: AMap = mapView.map
    override fun onCreate(bundle: Bundle) = mapView.onCreate(bundle)
    override fun onResume() = mapView.onResume()
    override fun onPause() = mapView.onPause()
    override fun onDestroy() = mapView.onDestroy()
}
