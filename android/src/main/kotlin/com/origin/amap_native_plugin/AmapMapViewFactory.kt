package com.origin.amap_native_plugin

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class AmapMapViewFactory(
    private val binaryMessenger: BinaryMessenger,
    createArgsCodec: MessageCodec<Any>
) : PlatformViewFactory(createArgsCodec) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<*, *>
        return AmapPlatformMapView(context, binaryMessenger, viewId, creationParams)
    }
}
