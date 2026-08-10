package com.resvg.mobile.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import com.resvg.mobile.FitMode
import com.resvg.mobile.RenderOptions
import com.resvg.mobile.Resvg
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlin.math.min

@Composable
fun ResvgImage(
    svg: ByteArray,
    modifier: Modifier = Modifier,
    fit: FitMode = FitMode.CONTAIN,
    contentScale: ContentScale = ContentScale.Fit,
    contentDescription: String? = null,
) {
    var size by remember { mutableStateOf(IntSize.Zero) }
    var bitmap by remember { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(svg, size, fit) {
        if (size.width <= 0 || size.height <= 0) return@LaunchedEffect
        // onSizeChanged reports pixels already — do not multiply by density again.
        val pixelW = max(1, min(size.width, 2048))
        val pixelH = max(1, min(size.height, 2048))
        val cacheKey = ResvgBitmapCache.key(svg.contentHashCode(), pixelW, pixelH, fit, 1f)
        ResvgBitmapCache.get(cacheKey)?.let {
            bitmap = it
            return@LaunchedEffect
        }
        val rendered = withContext(Dispatchers.Default) {
            runCatching {
                Resvg.renderBitmap(
                    svg,
                    RenderOptions(
                        width = pixelW.toUInt(),
                        height = pixelH.toUInt(),
                        fit = fit,
                        background = null,
                    ),
                    fontDirs = emptyList(),
                )
            }.getOrNull()
        }
        if (rendered != null) {
            ResvgBitmapCache.put(cacheKey, rendered)
        }
        bitmap = rendered
    }

    Box(
        modifier = modifier.onSizeChanged { size = it },
    ) {
        bitmap?.let {
            Image(
                bitmap = it.asImageBitmap(),
                contentDescription = contentDescription,
                contentScale = contentScale,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
