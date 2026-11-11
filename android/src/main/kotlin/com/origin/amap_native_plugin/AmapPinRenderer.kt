package com.origin.amap_native_plugin

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import io.flutter.FlutterInjector
import kotlin.math.ceil
import kotlin.math.max

internal class AmapPinRenderer(private val context: Context) {
    fun loadFlutterAssetBitmap(assetName: String): Bitmap? {
        return runCatching {
            val assetKey = FlutterInjector.instance()
                .flutterLoader()
                .getLookupKeyForAsset(assetName)
            context.assets.open(assetKey).use(BitmapFactory::decodeStream)
        }.getOrNull()
    }

    fun createCustomPinBitmap(
        label: String?,
        imageBitmap: Bitmap?,
        imageWidthDp: Float,
        imageHeightDp: Float,
        pinColor: Int,
        textColor: Int,
        backgroundColor: Int,
        labelTextScaleFactor: Float
    ): LabeledPinBitmap {
        val density = context.resources.displayMetrics.density
        val safeLabelTextScaleFactor = labelTextScaleFactor
            .takeIf { it.isFinite() && it > 0f }
            ?.coerceAtMost(4f)
            ?: 1f
        val pinWidth = (if (imageBitmap == null) 32f else imageWidthDp) * density
        val pinHeight = (if (imageBitmap == null) 42f else imageHeightDp) * density
        val gap = 6f * density
        val labelHeight = 32f * density * safeLabelTextScaleFactor
        val horizontalPadding = 10f * density * safeLabelTextScaleFactor
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColor
            textSize = 14f * density * safeLabelTextScaleFactor
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        val labelWidth = label?.let { textPaint.measureText(it) + horizontalPadding * 2 } ?: 0f
        val bitmapWidth = ceil(pinWidth + if (label == null) 0f else gap + labelWidth).toInt()
        val bitmapHeight = ceil(max(pinHeight, labelHeight)).toInt()
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        if (imageBitmap != null) {
            // Short marker images share the label's vertical center in the composed bitmap.
            val pinTop = (bitmapHeight - pinHeight).coerceAtLeast(0f) / 2f
            canvas.drawBitmap(
                imageBitmap,
                null,
                RectF(0f, pinTop, pinWidth, pinTop + pinHeight),
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            )
        } else {
            val pinPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = pinColor }
            val triangle = Path().apply {
                moveTo(8f * density, 21f * density)
                lineTo(pinWidth / 2f, pinHeight)
                lineTo(24f * density, 21f * density)
                close()
            }
            canvas.drawPath(triangle, pinPaint)
            canvas.drawCircle(pinWidth / 2f, 14f * density, 12f * density, pinPaint)
            canvas.drawCircle(
                pinWidth / 2f,
                14f * density,
                4f * density,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
            )
        }

        if (label != null) {
            val labelLeft = pinWidth + gap
            val labelTop = (bitmapHeight - labelHeight) / 2f
            val labelRect = RectF(labelLeft, labelTop, labelLeft + labelWidth, labelTop + labelHeight)
            canvas.drawRoundRect(
                labelRect,
                8f * density,
                8f * density,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = backgroundColor }
            )
            val baseline = labelRect.centerY() - (textPaint.ascent() + textPaint.descent()) / 2f
            canvas.drawText(label, labelLeft + horizontalPadding, baseline, textPaint)
        }

        return LabeledPinBitmap(bitmap, (pinWidth / 2f) / bitmapWidth.toFloat())
    }

}

internal data class LabeledPinBitmap(
    val bitmap: Bitmap,
    val anchorX: Float
)
