package com.origin.amap_native_plugin

import com.amap.api.maps.MapsInitializer
import com.amap.api.services.core.AMapException
import com.amap.api.services.core.LatLonPoint
import com.amap.api.services.core.ServiceSettings
import com.amap.api.services.help.Inputtips
import com.amap.api.services.help.InputtipsQuery
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMessageCodec

class AmapNativePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: android.content.Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "amap_native_plugin")
        channel.setMethodCallHandler(this)

        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "amap_native_plugin/map_view",
            AmapMapViewFactory(
                flutterPluginBinding.binaryMessenger,
                StandardMessageCodec.INSTANCE
            )
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
            else -> result.notImplemented()
        }
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

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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
