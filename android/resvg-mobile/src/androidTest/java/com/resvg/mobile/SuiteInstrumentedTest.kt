package com.resvg.mobile

import android.content.res.AssetManager
import android.os.Environment
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest

/**
 * Cross-platform SVG suite harness: render fixtures with the shared 512×512
 * Contain / transparent contract and write `path\tsha256\twidth\theight` JSONL.
 *
 * Assets are extracted to disk so usvg can resolve `../../../resources/...`
 * relative image hrefs (same layout as the vendor checkout).
 */
@RunWith(AndroidJUnit4::class)
class SuiteInstrumentedTest {

    @Test
    fun renderSuiteAndWriteResults() {
        val ctx = InstrumentationRegistry.getInstrumentation().context
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        val args = InstrumentationRegistry.getArguments()

        val manifestName = ctx.assets.open("manifest.txt").bufferedReader().use { it.readText().trim() }
            .ifEmpty { "smoke" }
        val dumpMismatch = args.getString("DUMP_MISMATCH") == "1" ||
            System.getenv("DUMP_MISMATCH") == "1"

        val outDir = target.getExternalFilesDir(null) ?: target.filesDir
        outDir.mkdirs()
        val resultsFile = File(outDir, "android-results.jsonl")
        val dumpRoot = File(outDir, "pixels")
        if (dumpMismatch) {
            dumpRoot.mkdirs()
        }

        val workRoot = File(target.filesDir, "suite-root")
        if (workRoot.exists()) {
            workRoot.deleteRecursively()
        }
        workRoot.mkdirs()
        extractAssetTree(ctx.assets, "suite", File(workRoot, "suite"))
        if (assetExists(ctx.assets, "resources")) {
            extractAssetTree(ctx.assets, "resources", File(workRoot, "resources"))
        }

        val paths = listSuitePaths(ctx.assets, manifestName)
        assertTrue("expected suite assets, got 0", paths.isNotEmpty())

        val fonts = if (manifestName == "full") {
            Resvg.loadAssetFontConfig(ctx, "suite-fonts")
        } else {
            emptyFontConfig
        }

        val options = RenderOptions(
            width = 512u,
            height = 512u,
            fit = FitMode.CONTAIN,
            background = Rgba(0u, 0u, 0u, 0u),
        )

        val lines = ArrayList<String>(paths.size)
        var failures = 0
        for (rel in paths) {
            try {
                val svgFile = File(workRoot, "suite/$rel")
                val svg = svgFile.readBytes()
                val resourcesDir = svgFile.parentFile?.absolutePath
                val img = renderWithResources(svg, options, fonts, resourcesDir)
                val sha = sha256Hex(img.rgba)
                lines.add("$rel\t$sha\t${img.width}\t${img.height}")
                if (dumpMismatch) {
                    val rgbaFile = File(dumpRoot, "$rel.rgba")
                    rgbaFile.parentFile?.mkdirs()
                    rgbaFile.writeBytes(img.rgba)
                    File(dumpRoot, "$rel.meta").writeText("${img.width} ${img.height}\n")
                }
            } catch (e: Exception) {
                failures++
                android.util.Log.e(TAG, "FAIL $rel: ${e.message}", e)
            }
        }

        resultsFile.writeText(lines.joinToString("\n", postfix = "\n"))

        try {
            val publicDir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "resvg-suite",
            )
            publicDir.mkdirs()
            val publicResults = File(publicDir, "android-results.jsonl")
            if (publicResults.exists()) {
                publicResults.delete()
            }
            resultsFile.inputStream().use { input ->
                publicResults.outputStream().use { output -> input.copyTo(output) }
            }
            if (dumpMismatch && dumpRoot.exists()) {
                val publicPixels = File(publicDir, "pixels")
                if (publicPixels.exists()) {
                    publicPixels.deleteRecursively()
                }
                dumpRoot.copyRecursively(publicPixels, overwrite = true)
            }
        } catch (e: Exception) {
            android.util.Log.w(TAG, "public copy skipped: ${e.message}")
        }

        android.util.Log.i(
            TAG,
            "Wrote ${lines.size} results to ${resultsFile.absolutePath} ($failures failures)",
        )
        val total = lines.size + failures
        val failRate = if (total == 0) 1.0 else failures.toDouble() / total
        // Smoke: zero tolerance. Full: match Rust ≤2% render-failure gate.
        val maxFailRate = if (manifestName == "full") 0.02 else 0.0
        assertTrue(
            "suite had $failures/$total render failures (rate=${"%.2f".format(failRate * 100)}%, max=${"%.0f".format(maxFailRate * 100)}%)",
            failRate <= maxFailRate,
        )
        assertTrue("results file missing", resultsFile.isFile)
    }

    private fun assetExists(assets: AssetManager, path: String): Boolean {
        return try {
            val children = assets.list(path)
            children != null && children.isNotEmpty()
        } catch (_: Exception) {
            false
        }
    }

    /** Recursively copy an asset folder onto the filesystem. */
    private fun extractAssetTree(assets: AssetManager, assetPath: String, destDir: File) {
        destDir.mkdirs()
        val children = assets.list(assetPath) ?: return
        for (name in children) {
            val childAsset = if (assetPath.isEmpty()) name else "$assetPath/$name"
            val childDest = File(destDir, name)
            val sub = assets.list(childAsset)
            if (sub.isNullOrEmpty()) {
                assets.open(childAsset).use { input ->
                    childDest.outputStream().use { output -> input.copyTo(output) }
                }
            } else {
                extractAssetTree(assets, childAsset, childDest)
            }
        }
    }

    private fun listSuitePaths(assets: AssetManager, manifest: String): List<String> {
        return when (manifest) {
            "smoke" -> {
                assets.open("smoke.txt").bufferedReader().useLines { lines ->
                    lines
                        .map { it.substringBefore('#').trim() }
                        .filter { it.isNotEmpty() }
                        .toList()
                }
            }
            "full" -> walkAssets(assets, "suite")
            else -> error("unknown manifest: $manifest")
        }
    }

    private fun walkAssets(assets: AssetManager, dir: String): List<String> {
        val out = ArrayList<String>()
        val children = assets.list(dir) ?: return out
        for (name in children) {
            val path = if (dir.isEmpty()) name else "$dir/$name"
            val sub = assets.list(path)
            if (sub.isNullOrEmpty()) {
                if (name.endsWith(".svg")) {
                    out.add(path.removePrefix("suite/"))
                }
            } else {
                out.addAll(walkAssets(assets, path))
            }
        }
        out.sort()
        return out
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { b -> "%02x".format(b) }
    }

    companion object {
        private const val TAG = "ResvgSuite"
    }
}
