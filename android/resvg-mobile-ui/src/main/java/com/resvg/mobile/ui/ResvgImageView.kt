package com.resvg.mobile.ui

import android.content.Context
import android.graphics.Bitmap
import android.util.AttributeSet
import androidx.appcompat.widget.AppCompatImageView
import com.resvg.mobile.FitMode
import com.resvg.mobile.RenderOptions
import com.resvg.mobile.Resvg
import kotlin.math.max
import kotlin.math.min
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

internal object ResvgBitmapCache {
    private const val CAPACITY = 64
    private val order = ArrayDeque<String>()
    private val map = ConcurrentHashMap<String, Bitmap>()

    @Synchronized
    fun get(key: String): Bitmap? {
        val bmp = map[key] ?: return null
        order.remove(key)
        order.addLast(key)
        return bmp
    }

    @Synchronized
    fun put(key: String, bitmap: Bitmap) {
        if (!map.containsKey(key)) {
            order.addLast(key)
        }
        map[key] = bitmap
        while (order.size > CAPACITY) {
            val oldest = order.removeFirst()
            map.remove(oldest)?.recycle()
        }
    }

    fun key(hash: Int, w: Int, h: Int, fit: FitMode, density: Float): String =
        "$hash|$w|x$h|$fit|$density"
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

    private val generation = AtomicInteger(0)
    private val executor = Executors.newSingleThreadExecutor()

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw || h != oldh) scheduleRender()
    }

    private fun scheduleRender() {
        val data = svgBytes ?: run {
            setImageBitmap(null)
            return
        }
        if (width <= 0 || height <= 0) return

        // View width/height are already in pixels.
        val pixelW = max(1, min(width, 2048))
        val pixelH = max(1, min(height, 2048))
        val cacheKey = ResvgBitmapCache.key(data.contentHashCode(), pixelW, pixelH, fit, 1f)
        ResvgBitmapCache.get(cacheKey)?.let {
            setImageBitmap(it)
            return
        }

        val gen = generation.incrementAndGet()
        val options = RenderOptions(
            width = pixelW.toUInt(),
            height = pixelH.toUInt(),
            fit = fit,
            background = null,
        )
        executor.execute {
            val bitmap = runCatching {
                Resvg.renderBitmap(data, options, fontDirs = emptyList())
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
