package com.resvg.mobile.ui

import android.content.Context
import android.graphics.Bitmap
import android.util.AttributeSet
import androidx.appcompat.widget.AppCompatImageView
import com.resvg.mobile.FitMode
import com.resvg.mobile.FontConfig
import com.resvg.mobile.RenderOptions
import com.resvg.mobile.Resvg
import com.resvg.mobile.cacheSignature
import com.resvg.mobile.emptyFontConfig
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlin.math.min

/**
 * Shared LRU keyed by content digest + render params.
 *
 * Eviction does **not** call [Bitmap.recycle]; consumers may still hold the
 * bitmap. Bound is approximate byte cost, not entry count.
 */
internal object ResvgBitmapCache {
    private const val MAX_BYTES: Long = 32L * 1024L * 1024L // 32 MiB
    private val order = ArrayDeque<String>()
    private val map = ConcurrentHashMap<String, Entry>()
    private var totalBytes: Long = 0

    private data class Entry(val bitmap: Bitmap, val bytes: Long)

    fun digest(svg: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        val hash = md.digest(svg)
        return hash.joinToString("") { b -> "%02x".format(b) }
    }

    fun key(
        digest: String,
        w: Int,
        h: Int,
        fit: FitMode,
        fontSig: String,
    ): String = "$digest|${w}x$h|$fit|$fontSig"

    @Synchronized
    fun get(key: String): Bitmap? {
        val entry = map[key] ?: return null
        order.remove(key)
        order.addLast(key)
        return entry.bitmap
    }

    @Synchronized
    fun put(key: String, bitmap: Bitmap) {
        val bytes = bitmap.byteCount.toLong().coerceAtLeast(1L)
        map[key]?.let { old ->
            totalBytes -= old.bytes
            order.remove(key)
        }
        map[key] = Entry(bitmap, bytes)
        order.addLast(key)
        totalBytes += bytes
        while (totalBytes > MAX_BYTES && order.isNotEmpty()) {
            val oldest = order.removeFirst()
            map.remove(oldest)?.let { totalBytes -= it.bytes }
        }
    }
}

private object ResvgRenderExecutor {
    val shared: ExecutorService =
        Executors.newFixedThreadPool(
            (Runtime.getRuntime().availableProcessors().coerceAtLeast(2) / 2).coerceAtLeast(1),
        )
}

/** View that rasterizes SVG bytes off the main thread with an LRU cache. */
class ResvgImageView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : AppCompatImageView(context, attrs, defStyleAttr) {

    var svgBytes: ByteArray? = null
        set(value) {
            field = value
            scheduleRender()
        }

    var fit: FitMode = FitMode.CONTAIN
        set(value) {
            field = value
            scheduleRender()
        }

    var fonts: FontConfig = emptyFontConfig
        set(value) {
            field = value
            scheduleRender()
        }

    private val generation = AtomicInteger(0)

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw || h != oldh) scheduleRender()
    }

    private fun scheduleRender() {
        val gen = generation.incrementAndGet()
        val data = svgBytes
        if (data == null) {
            setImageBitmap(null)
            return
        }
        if (width <= 0 || height <= 0) return

        val pixelW = max(1, min(width, Resvg.UI_MAX_RENDER_EDGE))
        val pixelH = max(1, min(height, Resvg.UI_MAX_RENDER_EDGE))
        val fonts = fonts
        val cacheKey = ResvgBitmapCache.key(
            ResvgBitmapCache.digest(data),
            pixelW,
            pixelH,
            fit,
            fonts.cacheSignature(),
        )
        ResvgBitmapCache.get(cacheKey)?.let {
            setImageBitmap(it)
            return
        }

        val options = RenderOptions(
            width = pixelW.toUInt(),
            height = pixelH.toUInt(),
            fit = fit,
            background = null,
        )
        val svg = data
        ResvgRenderExecutor.shared.execute {
            val bitmap = runCatching {
                Resvg.renderBitmap(svg, options, fonts)
            }.getOrNull()
            if (bitmap != null) {
                ResvgBitmapCache.put(cacheKey, bitmap)
            }
            post {
                if (generation.get() == gen) {
                    setImageBitmap(bitmap)
                }
            }
        }
    }
}
