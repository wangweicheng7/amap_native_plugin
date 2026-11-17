package com.origin.amap_native_plugin

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.amap.api.services.core.AMapException
import com.amap.api.services.core.LatLonPoint
import com.amap.api.services.core.ServiceSettings
import com.amap.api.services.geocoder.GeocodeSearch
import com.amap.api.services.geocoder.GeocodeResult
import com.amap.api.services.geocoder.RegeocodeQuery
import com.amap.api.services.geocoder.RegeocodeResult
import com.amap.api.services.help.Inputtips
import com.amap.api.services.help.InputtipsQuery
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

internal class AmapSearchHandler(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private data class Pending(val result: Result, val timeout: Runnable, val owner: Any)
    private val pending = mutableMapOf<String, Pending>()
    private var initialized = false

    fun initialize(key: String?, shown: Boolean, agreed: Boolean) {
        dispose()
        ServiceSettings.updatePrivacyShow(context, shown, shown)
        ServiceSettings.updatePrivacyAgree(context, agreed)
        if (!key.isNullOrBlank()) ServiceSettings.getInstance().setApiKey(key.trim())
        initialized = shown && agreed
    }

    fun handle(call: MethodCall, result: Result) {
        val id = call.argument<String>("requestId").orEmpty()
        if (call.method == "cancelSearch") {
            finish(id, error = "cancelled", message = "Search cancelled.")
            result.success(null)
            return
        }
        if (!initialized) {
            result.error("not_initialized", "Initialize AMap with privacy consent before searching.", null)
            return
        }
        if (id.isEmpty() || pending.containsKey(id)) {
            result.error("invalid_argument", "A unique requestId is required.", null)
            return
        }
        try {
            when (call.method) {
                "searchPlaces" -> searchPlaces(id, call, result)
                "reverseGeocode" -> reverseGeocode(id, call, result)
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            if (pending.containsKey(id)) {
                fail(id, error)
            } else {
                val vendorCode = (error as? AMapException)?.errorCode
                val code = if (error is IllegalArgumentException) "invalid_argument"
                    else vendorCode?.let(::errorCode) ?: "sdk_error"
                result.error(code, error.message, vendorCode?.let { mapOf("vendorCode" to it) })
            }
        }
    }

    private fun register(id: String, call: MethodCall, result: Result, owner: Any) {
        val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 15000L
        require(timeoutMs in 1..60000)
        val timer = Runnable { finish(id, error = "timeout", message = "AMap search timed out.") }
        pending[id] = Pending(result, timer, owner)
        handler.postDelayed(timer, timeoutMs)
    }

    private fun point(value: Map<String, Number>?): LatLonPoint? {
        if (value == null) return null
        val latitude = value["latitude"]?.toDouble() ?: error("latitude is required.")
        val longitude = value["longitude"]?.toDouble() ?: error("longitude is required.")
        require(latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0)
        return LatLonPoint(latitude, longitude)
    }

    private fun searchPlaces(id: String, call: MethodCall, result: Result) {
        val keyword = call.argument<String>("keyword")?.trim().orEmpty()
        require(keyword.isNotEmpty() && keyword.length <= 80)
        val query = InputtipsQuery(keyword, call.argument<String>("city").orEmpty())
        query.cityLimit = call.argument<Boolean>("cityLimit") ?: false
        point(call.argument<Map<String, Number>>("location"))?.let { query.location = it }
        val search = Inputtips(context, query)
        register(id, call, result, search)
        search.setInputtipsListener { tips, code ->
            handler.post {
                if (code != 1000) {
                    finish(id, error = errorCode(code), message = "AMap input tips failed.", vendorCode = code)
                } else {
                    finish(id, value = tips.orEmpty().map { tip ->
                        mapOf(
                            "id" to tip.poiID.orEmpty(),
                            "name" to tip.name.orEmpty(),
                            "address" to tip.address.orEmpty(),
                            "district" to tip.district.orEmpty(),
                            "adCode" to tip.adcode.orEmpty(),
                            "latitude" to tip.point?.latitude,
                            "longitude" to tip.point?.longitude
                        )
                    })
                }
            }
        }
        search.requestInputtipsAsyn()
    }

    private fun reverseGeocode(id: String, call: MethodCall, result: Result) {
        val position = requireNotNull(point(call.argument<Map<String, Number>>("position")))
        val radius = call.argument<Number>("radiusMeters")?.toDouble() ?: 200.0
        require(radius.isFinite() && radius in 1.0..3000.0)
        val search = GeocodeSearch(context)
        register(id, call, result, search)
        search.setOnGeocodeSearchListener(object : GeocodeSearch.OnGeocodeSearchListener {
            override fun onGeocodeSearched(value: GeocodeResult?, code: Int) {}
            override fun onRegeocodeSearched(value: RegeocodeResult?, code: Int) {
                handler.post {
                    if (code != 1000) {
                        finish(id, error = errorCode(code), message = "AMap reverse geocoding failed.", vendorCode = code)
                    } else {
                        val address = value?.regeocodeAddress
                        val fields = address?.let {
                            mapOf(
                                "formattedAddress" to it.formatAddress.orEmpty(),
                                "province" to it.province.orEmpty(),
                                "city" to it.city.orEmpty(),
                                "district" to it.district.orEmpty(),
                                "adCode" to it.adCode.orEmpty()
                            )
                        }
                        finish(id, value = fields?.takeIf { it.values.any(String::isNotBlank) })
                    }
                }
            }
        })
        search.getFromLocationAsyn(RegeocodeQuery(position, radius.toFloat(), GeocodeSearch.AMAP))
    }

    private fun errorCode(code: Int): String = when (code) {
        1004, 1005, 1010 -> "rate_limited"
        in 1001..1014 -> "auth_error"
        1102, 1103, 1802 -> "timeout"
        1804, 1805, 1806 -> "network_error"
        1200, 1201, 1202, 1813 -> "invalid_argument"
        1807 -> "cancelled"
        else -> "sdk_error"
    }

    private fun fail(id: String, error: Exception) {
        val vendorCode = (error as? AMapException)?.errorCode
        finish(id, error = vendorCode?.let(::errorCode) ?: "sdk_error", message = error.message, vendorCode = vendorCode)
    }

    private fun finish(
        id: String,
        value: Any? = null,
        error: String? = null,
        message: String? = null,
        vendorCode: Int? = null
    ) {
        val request = pending.remove(id) ?: return
        handler.removeCallbacks(request.timeout)
        if (error == null) request.result.success(value)
        else request.result.error(error, message, vendorCode?.let { mapOf("vendorCode" to it) })
    }

    fun dispose() {
        initialized = false
        pending.keys.toList().forEach { finish(it, error = "cancelled", message = "Search service detached or reinitialized.") }
    }
}
