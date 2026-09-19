package com.resvg.mobile.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil3.ImageLoader
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.resvg.mobile.coil.ResvgDecoder
import com.resvg.mobile.ui.ResvgImage

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val context = LocalContext.current
            val svg = remember {
                assets.open("sample.svg").use { it.readBytes() }
            }
            val imageLoader = remember {
                ImageLoader.Builder(context)
                    .components { add(ResvgDecoder.Factory()) }
                    .build()
            }
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = Color(0xFF0F172A)) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = "resvg-mobile demo",
                            color = Color.White,
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(
                            text = "ResvgImage + Coil AsyncImage",
                            color = Color(0xFF94A3B8),
                            modifier = Modifier.padding(top = 8.dp, bottom = 24.dp),
                        )
                        ResvgImage(
                            svg = svg,
                            modifier = Modifier
                                .size(160.dp)
                                .background(Color(0xFF1E293B))
                                .padding(20.dp),
                            contentDescription = "Sample SVG (ResvgImage)",
                        )
                        Text(
                            text = "Coil 3 + ResvgDecoder",
                            color = Color(0xFF94A3B8),
                            modifier = Modifier.padding(top = 24.dp, bottom = 12.dp),
                        )
                        AsyncImage(
                            model = ImageRequest.Builder(context)
                                .data(svg)
                                .crossfade(true)
                                .build(),
                            contentDescription = "Sample SVG (Coil)",
                            imageLoader = imageLoader,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier
                                .size(160.dp)
                                .background(Color(0xFF1E293B))
                                .padding(20.dp),
                        )
                    }
                }
            }
        }
    }
}
