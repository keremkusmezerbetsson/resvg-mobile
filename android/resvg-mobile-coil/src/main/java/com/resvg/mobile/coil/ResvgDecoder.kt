package com.resvg.mobile.coil

import coil3.Extras
import coil3.ImageLoader
import coil3.asImage
import coil3.decode.DecodeResult
import coil3.decode.Decoder
import coil3.decode.ImageSource
import coil3.fetch.SourceFetchResult
import coil3.getExtra
import coil3.request.ImageRequest
import coil3.request.Options
import coil3.size.Dimension
import coil3.size.Scale
import coil3.size.Size
import coil3.size.isOriginal
import com.resvg.mobile.FitMode
import com.resvg.mobile.FontConfig
import com.resvg.mobile.RenderOptions
import com.resvg.mobile.Resvg
import com.resvg.mobile.emptyFontConfig
import okio.BufferedSource
import okio.ByteString.Companion.encodeUtf8
import kotlin.math.min

/**
 * Coil 3 [Decoder] that rasterizes SVG with [Resvg].
 *
 * Does not pass `resourcesDir`, so remote SVG cannot open local files (absolute hrefs included).
 *
 * Register with:
 * ```
 * ImageLoader.Builder(context)
 *   .components { add(ResvgDecoder.Factory()) }
 *   .build()
 * ```
 */
class ResvgDecoder(
    private val source: ImageSource,
    private val options: Options,
    private val defaultFonts: FontConfig,
) : Decoder {

    override suspend fun decode(): DecodeResult {
        val svg = source.source().use { it.readByteArray() }
        val requestFonts = options.resvgFonts
        val fonts = if (requestFonts !== emptyFontConfig) requestFonts else defaultFonts
        val renderOptions = options.size.toRenderOptions(options.scale)
        val bitmap = Resvg.renderBitmap(svg, renderOptions, fonts)
        val sampled = renderOptions.fit != FitMode.INTRINSIC
        return DecodeResult(
            image = bitmap.asImage(),
            isSampled = sampled,
        )
    }

    class Factory(
        private val defaultFonts: FontConfig = emptyFontConfig,
    ) : Decoder.Factory {
        override fun create(
            result: SourceFetchResult,
            options: Options,
            imageLoader: ImageLoader,
        ): Decoder? {
            if (!isSvg(result.mimeType, result.source.source())) {
                return null
            }
            return ResvgDecoder(result.source, options, defaultFonts)
        }
    }
}

/** Attach fonts for this request (overrides [ResvgDecoder.Factory] defaults). */
fun ImageRequest.Builder.resvgFonts(fonts: FontConfig) = apply {
    extras[resvgFontsKey] = fonts
}

/** Default fonts for every request on this loader (request-level [resvgFonts] wins). */
fun ImageLoader.Builder.resvgFonts(fonts: FontConfig) = apply {
    extras[resvgFontsKey] = fonts
}

val Options.resvgFonts: FontConfig
    get() = getExtra(resvgFontsKey)

private val resvgFontsKey = Extras.Key(default = emptyFontConfig)

private fun isSvg(mimeType: String?, source: BufferedSource): Boolean {
    val mime = mimeType?.lowercase()
    if (mime == "image/svg+xml") return true
    // Peek only — do not consume the source (Coil may try other decoders).
    if (source.rangeEquals(0, SVG_TAG)) return true
    if (source.rangeEquals(0, XML_DECL)) {
        return source.indexOf(SVG_TAG, 0, SEARCH_LIMIT) != -1L
    }
    return source.indexOf(SVG_TAG, 0, SEARCH_LIMIT) != -1L
}

private fun Size.toRenderOptions(scale: Scale): RenderOptions {
    if (isOriginal) {
        return RenderOptions(
            width = null,
            height = null,
            fit = FitMode.INTRINSIC,
            background = null,
        )
    }
    val widthPx = (width as? Dimension.Pixels)?.px
    val heightPx = (height as? Dimension.Pixels)?.px
    if (widthPx == null || heightPx == null || widthPx <= 0 || heightPx <= 0) {
        return RenderOptions(
            width = null,
            height = null,
            fit = FitMode.INTRINSIC,
            background = null,
        )
    }
    val w = min(widthPx, Resvg.UI_MAX_RENDER_EDGE).toUInt()
    val h = min(heightPx, Resvg.UI_MAX_RENDER_EDGE).toUInt()
    val fit = when (scale) {
        Scale.FILL -> FitMode.COVER
        Scale.FIT -> FitMode.CONTAIN
    }
    return RenderOptions(
        width = w,
        height = h,
        fit = fit,
        background = null,
    )
}

private val SVG_TAG = "<svg".encodeUtf8()
private val XML_DECL = "<?xml".encodeUtf8()
private const val SEARCH_LIMIT = 2_048L
