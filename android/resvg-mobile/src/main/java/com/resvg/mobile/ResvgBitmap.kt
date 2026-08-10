package com.resvg.mobile

import android.graphics.Bitmap

/**
 * Idiomatic Android helpers around UniFFI-generated raster APIs.
 *
 * Prefer calling [renderBitmap] off the main thread for large SVGs.
 *
 * Note: UniFFI `bytes` maps to [ByteArray] (not boxed `List<UByte>`), which is
 * required to avoid OOM when returning large RGBA buffers.
 */
object Resvg {
    /** Empty by default — loading all of `/system/fonts` is very expensive. */
    val defaultFontDirs: List<String> = emptyList()

    private const val MAX_RENDER_EDGE = 2048

    @JvmStatic
    @JvmOverloads
    fun renderBitmap(
        svg: ByteArray,
        options: RenderOptions = RenderOptions(
            width = null,
            height = null,
            fit = FitMode.CONTAIN,
            background = null,
        ),
        fontDirs: List<String> = defaultFontDirs,
    ): Bitmap {
        val safe = options.capped()
        val rendered = if (fontDirs.isEmpty()) {
            render(svg, safe)
        } else {
            renderWithFonts(svg, safe, fontDirs)
        }
        return rendered.toBitmap()
    }

    @JvmStatic
    fun intrinsicSizePx(svg: ByteArray): Pair<Float, Float> {
        val size = intrinsicSize(svg)
        return size.width to size.height
    }

    private fun RenderOptions.capped(): RenderOptions {
        val w = width?.toInt()?.coerceIn(1, MAX_RENDER_EDGE)?.toUInt()
        val h = height?.toInt()?.coerceIn(1, MAX_RENDER_EDGE)?.toUInt()
        return RenderOptions(width = w, height = h, fit = fit, background = background)
    }
}

/** Convert straight RGBA bytes to an [Bitmap.Config.ARGB_8888] bitmap. */
fun RenderedImage.toBitmap(): Bitmap {
    require(width > 0u && height > 0u) { "invalid size" }
    val w = width.toInt()
    val h = height.toInt()
    require(rgba.size == w * h * 4) { "RGBA length mismatch" }

    val pixels = IntArray(w * h)
    var i = 0
    var p = 0
    while (i < rgba.size) {
        val r = rgba[i].toInt() and 0xFF
        val g = rgba[i + 1].toInt() and 0xFF
        val b = rgba[i + 2].toInt() and 0xFF
        val a = rgba[i + 3].toInt() and 0xFF
        pixels[p++] = (a shl 24) or (r shl 16) or (g shl 8) or b
        i += 4
    }

    return Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888)
}
