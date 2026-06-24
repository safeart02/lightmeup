package com.example.lightmeup

import android.graphics.Bitmap
import android.graphics.Color

/**
 * Extracts representative colours from the left and right edges of a [Bitmap]
 * to drive the corresponding joystick LEDs.
 *
 * Algorithm:
 *   1. Sample a grid of pixels within the zone (avoids reading every pixel).
 *   2. Average R, G, B channels separately (perceptually reasonable for LEDs).
 *   3. Apply exponential smoothing between frames so colours transition
 *      gradually rather than snapping abruptly.
 */
object ColorSampler {

    // Grid density: we sample every Nth pixel within the zone.
    private const val SAMPLE_STEP = 4

    // Current smoothed colours (ARGB ints). Updated each frame.
    private var smoothLeft  = Color.WHITE
    private var smoothRight = Color.WHITE

    /**
     * Sample [bitmap], returning a [Pair] of (leftArgb, rightArgb).
     *
     * @param bitmap     The downscaled screen capture.
     * @param zoneWidth  Fraction of bitmap width to sample (e.g. 0.15 = 15%).
     * @param smoothing  Smoothing factor 0.0 (instant) … 0.95 (very slow).
     */
    fun sample(bitmap: Bitmap, zoneWidth: Float, smoothing: Float): Pair<Int, Int> {
        val w = bitmap.width
        val h = bitmap.height
        val zonePixels = (w * zoneWidth).toInt().coerceAtLeast(1)

        val rawLeft  = averageZone(bitmap, 0,           zonePixels, h)
        val rawRight = averageZone(bitmap, w - zonePixels, zonePixels, h)

        // Exponential smoothing
        smoothLeft  = lerpColor(smoothLeft,  rawLeft,  1f - smoothing)
        smoothRight = lerpColor(smoothRight, rawRight, 1f - smoothing)

        return Pair(smoothLeft, smoothRight)
    }

    /** Reset smoothed state (call when service starts fresh). */
    fun reset() {
        smoothLeft  = Color.WHITE
        smoothRight = Color.WHITE
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private fun averageZone(bitmap: Bitmap, startX: Int, width: Int, height: Int): Int {
        var r = 0L; var g = 0L; var b = 0L; var count = 0L

        val endX = (startX + width).coerceAtMost(bitmap.width)
        var x = startX
        while (x < endX) {
            var y = 0
            while (y < height) {
                val px = bitmap.getPixel(x, y)
                r += Color.red(px)
                g += Color.green(px)
                b += Color.blue(px)
                count++
                y += SAMPLE_STEP
            }
            x += SAMPLE_STEP
        }

        if (count == 0L) return Color.BLACK
        return Color.rgb((r / count).toInt(), (g / count).toInt(), (b / count).toInt())
    }

    private fun lerpColor(from: Int, to: Int, t: Float): Int {
        val t2 = t.coerceIn(0f, 1f)
        val r = lerp(Color.red(from),   Color.red(to),   t2)
        val g = lerp(Color.green(from), Color.green(to), t2)
        val b = lerp(Color.blue(from),  Color.blue(to),  t2)
        return Color.rgb(r, g, b)
    }

    private fun lerp(a: Int, b: Int, t: Float): Int =
        (a + (b - a) * t).toInt().coerceIn(0, 255)
}
