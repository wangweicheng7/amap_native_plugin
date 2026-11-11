package com.origin.amap_native_plugin

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import com.amap.api.maps.AMap
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

internal class AmapSnapshotController(private val map: AMap) {
    private class Request(val result: Result) {
        val callbackAccepted = AtomicBoolean(false)
        val completed = AtomicBoolean(false)
        lateinit var timeout: Runnable
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val encoder = Executors.newSingleThreadExecutor()
    private var pending: Request? = null
    private var disposed = false

    fun capture(result: Result, ready: Boolean) {
        if (disposed) {
            result.error("map_disposed", "Map view has already been disposed", null)
            return
        }
        if (pending != null) {
            result.error("snapshot_in_progress", "A map snapshot is already in progress", null)
            return
        }
        if (!ready) {
            result.error("map_not_ready", "Map must be loaded, active, visible and have nonzero dimensions", null)
            return
        }
        val request = Request(result)
        request.timeout = Runnable { finish(request) { it.success(null) } }
        pending = request
        mainHandler.postDelayed(request.timeout, 5_000)
        try {
            map.getMapScreenShot(object : AMap.OnMapScreenShotListener {
                override fun onMapScreenShot(bitmap: Bitmap?) = acceptBitmap(request, bitmap)

                override fun onMapScreenShot(bitmap: Bitmap?, status: Int) = acceptBitmap(request, bitmap)
            })
        } catch (error: Exception) {
            finish(request) { it.error("snapshot_failed", error.message, null) }
        }
    }

    private fun acceptBitmap(request: Request, bitmap: Bitmap?) {
        if (request.completed.get() || !request.callbackAccepted.compareAndSet(false, true)) return
        if (bitmap == null) {
            mainHandler.post { finish(request) { it.success(null) } }
            return
        }
        // The SDK owns its bitmap. Only our independent copy crosses into the encoder thread.
        val copy = try {
            bitmap.copy(Bitmap.Config.ARGB_8888, false)
        } catch (error: Exception) {
            failOnMain(request, error.message)
            return
        } catch (_: OutOfMemoryError) {
            failOnMain(request, "Insufficient memory to copy the map snapshot")
            return
        }
        if (copy == null) {
            failOnMain(request, "The map snapshot could not be copied")
            return
        }
        if (request.completed.get()) {
            copy.recycle()
            return
        }
        try {
            encoder.execute {
                try {
                    if (request.completed.get()) return@execute
                    val bytes = ByteArrayOutputStream().use { stream ->
                        check(copy.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                            "The map snapshot could not be encoded as PNG"
                        }
                        stream.toByteArray()
                    }
                    mainHandler.post { finish(request) { it.success(bytes) } }
                } catch (error: Exception) {
                    failOnMain(request, error.message)
                } catch (_: OutOfMemoryError) {
                    failOnMain(request, "Insufficient memory to encode the map snapshot")
                } finally {
                    copy.recycle()
                }
            }
        } catch (_: RejectedExecutionException) {
            copy.recycle()
            failOnMain(request, "Map snapshot encoder is no longer available")
        }
    }

    private fun failOnMain(request: Request, message: String?) {
        mainHandler.post { finish(request) { it.error("snapshot_failed", message, null) } }
    }

    private fun finish(request: Request, reply: (Result) -> Unit) {
        if (pending !== request || !request.completed.compareAndSet(false, true)) return
        request.callbackAccepted.set(true)
        mainHandler.removeCallbacks(request.timeout)
        pending = null
        reply(request.result)
    }

    fun cancelPending() {
        pending?.let { request ->
            finish(request) { it.error("map_not_ready", "Map became inactive or hidden", null) }
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        pending?.let { request ->
            finish(request) { it.error("map_disposed", "Map view was disposed during the snapshot", null) }
        }
        // Let an accepted task run its finally block and release its bitmap copy.
        encoder.shutdown()
    }
}
