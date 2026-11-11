package com.origin.amap_native_plugin

import android.app.Activity
import android.app.Application
import android.os.Bundle
import com.amap.api.maps.MapsInitializer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMessageCodec

class AmapNativePlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: android.content.Context
    private var mapViewFactory: AmapMapViewFactory? = null
    private var currentActivity: Activity? = null
    private var activityCallbacks: Application.ActivityLifecycleCallbacks? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "amap_native_plugin")
        channel.setMethodCallHandler(this)

        mapViewFactory = AmapMapViewFactory(
            flutterPluginBinding.binaryMessenger,
            StandardMessageCodec.INSTANCE
        )
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "amap_native_plugin/map_view",
            mapViewFactory!!
        )
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> {
                val privacyShown = call.argument<Boolean>("privacyShown")
                    ?: call.argument<Boolean>("androidPrivacyShown")
                    ?: false
                val privacyAgreed = call.argument<Boolean>("privacyAgreed")
                    ?: call.argument<Boolean>("androidPrivacyAgreed")
                    ?: false
                val androidApiKey = call.argument<String>("androidApiKey")

                MapsInitializer.updatePrivacyShow(applicationContext, privacyShown, privacyShown)
                MapsInitializer.updatePrivacyAgree(applicationContext, privacyAgreed)
                setApiKeyIfSupported(androidApiKey)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /// Activity 生命周期桥接：把宿主 Activity 的 onResume/onPause 广播给所有活跃
    /// 地图实例，让高德 MapView 的 GL 生命周期（onResume/onPause）与 Activity 严格
    /// 配对。覆盖切后台、锁屏、键盘弹出（布局重建）、配置变更（旋转）等所有场景。
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        val callbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                if (activity === currentActivity) {
                    mapViewFactory?.onActivityResumed()
                }
            }

            override fun onActivityPaused(activity: Activity) {
                if (activity === currentActivity) {
                    mapViewFactory?.onActivityPaused()
                }
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        }
        activityCallbacks?.let {
            (applicationContext as Application).unregisterActivityLifecycleCallbacks(it)
        }
        (applicationContext as Application).registerActivityLifecycleCallbacks(callbacks)
        activityCallbacks = callbacks
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // 配置变更走 onReattachedToActivityForConfigChanges 更新引用，callbacks 保持注册。
    }

    override fun onDetachedFromActivity() {
        currentActivity = null
        mapViewFactory?.onActivityDetached()
        activityCallbacks?.let {
            (applicationContext as Application).unregisterActivityLifecycleCallbacks(it)
        }
        activityCallbacks = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        currentActivity = null
        mapViewFactory?.onActivityDetached()
        activityCallbacks?.let {
            (applicationContext as Application).unregisterActivityLifecycleCallbacks(it)
        }
        activityCallbacks = null
        mapViewFactory = null
        channel.setMethodCallHandler(null)
    }

    private fun setApiKeyIfSupported(apiKey: String?) {
        if (apiKey.isNullOrBlank()) {
            return
        }

        runCatching {
            MapsInitializer::class.java
                .getMethod("setApiKey", String::class.java)
                .invoke(null, apiKey)
        }
    }
}
