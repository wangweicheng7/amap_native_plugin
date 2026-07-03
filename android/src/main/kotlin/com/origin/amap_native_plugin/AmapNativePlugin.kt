package com.origin.amap_native_plugin

import com.amap.api.maps.MapsInitializer
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
                setApiKeyIfSupported(androidApiKey)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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
