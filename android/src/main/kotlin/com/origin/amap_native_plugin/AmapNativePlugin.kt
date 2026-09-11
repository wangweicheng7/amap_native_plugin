package com.origin.amap_native_plugin

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.Build
import com.amap.api.maps.MapsInitializer
import com.amap.api.services.core.AMapException
import com.amap.api.services.core.LatLonPoint
import com.amap.api.services.core.ServiceSettings
import com.amap.api.services.help.Inputtips
import com.amap.api.services.help.InputtipsQuery
import java.util.Locale
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
                val androidPrivacyShown = call.argument<Boolean>("androidPrivacyShown") ?: true
                val androidPrivacyAgreed = call.argument<Boolean>("androidPrivacyAgreed") ?: true
                val androidApiKey = call.argument<String>("androidApiKey")

                MapsInitializer.updatePrivacyShow(applicationContext, true, androidPrivacyShown)
                MapsInitializer.updatePrivacyAgree(applicationContext, androidPrivacyAgreed)
                ServiceSettings.updatePrivacyShow(applicationContext, true, androidPrivacyShown)
                ServiceSettings.updatePrivacyAgree(applicationContext, androidPrivacyAgreed)
                setApiKeyIfSupported(androidApiKey)
                result.success(null)
            }
            "searchPlaces" -> searchPlaces(call, result)
            "shouldUseNativeMap" -> result.success(!isEmulator())
            else -> result.notImplemented()
        }
    }

    private fun isEmulator(): Boolean {
        val fingerprint = (Build.FINGERPRINT ?: "").lowercase(Locale.ROOT)
        val model = (Build.MODEL ?: "").lowercase(Locale.ROOT)
        val brand = (Build.BRAND ?: "").lowercase(Locale.ROOT)
        val manufacturer = (Build.MANUFACTURER ?: "").lowercase(Locale.ROOT)
        val product = (Build.PRODUCT ?: "").lowercase(Locale.ROOT)
        val hardware = (Build.HARDWARE ?: "").lowercase(Locale.ROOT)
        return fingerprint.startsWith("generic") ||
            fingerprint.startsWith("unknown") ||
            model.contains("sdk_gphone") ||
            model.contains("emulator") ||
            model.contains("android sdk") ||
            brand.startsWith("generic") ||
            brand == "generic_x86" ||
            manufacturer.contains("genymotion") ||
            product == "sdk" ||
            product == "sdk_x86" ||
            product == "sdk_gphone_x86" ||
            hardware == "goldfish" ||
            hardware == "ranchu" ||
            hardware == "vbox86"
    }

    private fun searchPlaces(call: MethodCall, result: Result) {
        val keyword = call.argument<String>("keyword")?.trim().orEmpty()
        if (keyword.length < 2) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        val query = InputtipsQuery(keyword, "").apply {
            cityLimit = false
            val latitude = call.argument<Double>("latitude")
            val longitude = call.argument<Double>("longitude")
            if (latitude != null && longitude != null) {
                location = LatLonPoint(latitude, longitude)
            }
        }
        val inputtips = Inputtips(applicationContext, query)
        inputtips.setInputtipsListener { tips, code ->
            if (code != AMapException.CODE_AMAP_SUCCESS) {
                result.error("AMAP_SEARCH_$code", "地点搜索失败（$code）", null)
                return@setInputtipsListener
            }
            val places = tips.orEmpty().mapNotNull { tip ->
                val point = tip.point ?: return@mapNotNull null
                mapOf(
                    "name" to tip.name.orEmpty(),
                    "latitude" to point.latitude,
                    "longitude" to point.longitude,
                    "district" to tip.district.orEmpty(),
                    "address" to tip.address.orEmpty(),
                )
            }
            result.success(places)
        }
        inputtips.requestInputtipsAsyn()
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
            ServiceSettings.getInstance().setApiKey(apiKey)
            MapsInitializer::class.java
                .getMethod("setApiKey", String::class.java)
                .invoke(null, apiKey)
        }
    }
}
