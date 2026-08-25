package com.resvg.mobile

import android.content.Context
import android.graphics.Bitmap
import java.security.MessageDigest
import java.util.Collections
import java.util.WeakHashMap

/** Icon-only default — no directories, bytes, or aliases. */
val emptyFontConfig: FontConfig = fontConfig()

fun fontConfig(
    dirs: List<String> = emptyList(),
    data: List<ByteArray> = emptyList(),
    aliases: List<FontAlias> = emptyList(),
    defaultFamily: String? = null,
): FontConfig = FontConfig(
    dirs = dirs,
    data = data,
    aliases = aliases,
    defaultFamily = defaultFamily,
)

fun FontConfig.isConfigured(): Boolean =
    dirs.isNotEmpty() || data.isNotEmpty() || aliases.isNotEmpty() || defaultFamily != null

fun FontConfig.cacheSignature(): String {
    val dataSig = data.joinToString(",") { it.stableFingerprint() }
    val aliasSig = aliases.joinToString(",") { "${it.requested}=${it.replacement}" }
    return "${dirs.joinToString(",")}|$dataSig|$aliasSig|${defaultFamily.orEmpty()}"
}

private val fontBlobFingerprints = Collections.synchronizedMap(WeakHashMap<ByteArray, String>())

private fun ByteArray.stableFingerprint(): String =
    fontBlobFingerprints.getOrPut(this) {
        MessageDigest.getInstance("SHA-256").digest(this)
            .joinToString("") { b -> "%02x".format(b) }
            .substring(0, 16)
    }

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

    /**
     * Soft edge cap applied only by UI wrappers. The core library enforces its
     * own [MAX_DIMENSION]/[MAX_PIXELS] limits; this adapter does not silently
     * clamp caller-requested sizes.
     */
    const val UI_MAX_RENDER_EDGE: Int = 2048

    @JvmStatic
    @JvmOverloads
    fun renderBitmap(
        svg: ByteArray,
        options: RenderOptions = RenderOptions(
            width = null,
            height = null,
            fit = FitMode.INTRINSIC,
            background = null,
        ),
        fonts: FontConfig = emptyFontConfig,
    ): Bitmap {
        val rendered = if (fonts.isConfigured()) {
            renderWithFontConfig(svg, options, fonts)
        } else {
            render(svg, options)
        }
        return rendered.toBitmap()
    }

    /**
     * Common CSS / system family names → faces in the resvg-test-suite font set.
     */
    @JvmField
    val defaultFontAliases: List<FontAlias> = listOf(
        FontAlias(requested = "sans-serif", replacement = "Noto Sans"),
        FontAlias(requested = "serif", replacement = "Noto Serif"),
        FontAlias(requested = "monospace", replacement = "Noto Mono"),
        FontAlias(requested = "cursive", replacement = "Yellowtail"),
        FontAlias(requested = "fantasy", replacement = "Sedgwick Ave Display"),
        FontAlias(requested = "Arial", replacement = "Noto Sans"),
        FontAlias(requested = "Helvetica", replacement = "Noto Sans"),
        FontAlias(requested = "Helvetica Neue", replacement = "Noto Sans"),
        FontAlias(requested = "system-ui", replacement = "Noto Sans"),
        FontAlias(requested = "Times New Roman", replacement = "Noto Serif"),
        FontAlias(requested = "Courier New", replacement = "Noto Mono"),
    )

    /** Load TTF/OTF/TTC files from an assets folder as raw font bytes. */
    @JvmStatic
    @JvmOverloads
    fun loadAssetFonts(context: Context, folder: String = "suite-fonts"): List<ByteArray> {
        val names = context.assets.list(folder).orEmpty()
            .filter {
                it.endsWith(".ttf", ignoreCase = true) ||
                    it.endsWith(".otf", ignoreCase = true) ||
                    it.endsWith(".ttc", ignoreCase = true)
            }
            .sorted()
        return names.map { name ->
            context.assets.open("$folder/$name").use { it.readBytes() }
        }
    }

    /** In-memory fonts + aliases. Prefer this on Android over extracting asset dirs. */
    @JvmStatic
    @JvmOverloads
    fun loadAssetFontConfig(
        context: Context,
        folder: String = "suite-fonts",
        aliases: List<FontAlias> = defaultFontAliases,
        defaultFamily: String? = "Noto Sans",
    ): FontConfig {
        return fontConfig(
            data = loadAssetFonts(context, folder),
            aliases = aliases,
            defaultFamily = defaultFamily,
        )
    }

    @JvmStatic
    fun intrinsicSizePx(svg: ByteArray): Pair<Float, Float> {
        val size = intrinsicSize(svg)
        return size.width to size.height
    }
}

/** Convert straight RGBA bytes to an [Bitmap.Config.ARGB_8888] bitmap. */
fun RenderedImage.toBitmap(): Bitmap {
    require(width > 0u && height > 0u) { "invalid size" }
    val w = width.toInt()
    val h = height.toInt()
    require(rgba.size == w * h * 4) { "RGBA length mismatch" }

    val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
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
    bitmap.setPixels(pixels, 0, w, 0, 0, w, h)
    return bitmap
}
