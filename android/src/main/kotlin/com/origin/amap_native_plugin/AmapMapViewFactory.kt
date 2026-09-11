package com.origin.amap_native_plugin

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.CopyOnWriteArrayList

class AmapMapViewFactory(
    private val binaryMessenger: BinaryMessenger,
    createArgsCodec: MessageCodec<Any>
) : PlatformViewFactory(createArgsCodec) {
    /// 追踪所有存活的地图实例；create() 注册、dispose() 经 onDisposed 回调自动移除。
    private val activeViews = CopyOnWriteArrayList<AmapPlatformMapView>()

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<*, *>
        val view = AmapPlatformMapView(
            context,
            binaryMessenger,
            viewId,
            creationParams,
            onDisposed = { activeViews.remove(it) }
        )
        activeViews.add(view)
        return view
    }

    /// Activity 生命周期广播（由 AmapNativePlugin 在 ActivityAware 回调里调用），
    /// 逐个配对每个活跃地图的 GL 生命周期。
    fun onActivityResumed() {
        activeViews.forEach { it.onHostResumed() }
    }

    fun onActivityPaused() {
        activeViews.forEach { it.onHostPaused() }
    }

    /// Activity detach（销毁/plugin 解绑）时兜底挂起，幂等。
    fun onActivityDetached() {
        activeViews.forEach { it.onHostPaused() }
    }
}
