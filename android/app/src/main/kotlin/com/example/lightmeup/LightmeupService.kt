package com.example.lightmeup

import android.app.*
import android.graphics.Color
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import kotlin.math.*

class LightmeupService : Service() {

    companion object {
        private const val TAG      = "LightmeupService"
        private const val NOTIF_ID = 1001
        private const val CHANNEL_ID = "lightmeup_channel"

        private const val CAPTURE_W = 160
        private const val CAPTURE_H = 90

        // ── Start intent extras ────────────────────────────────────────────
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_DATA        = "data"
        const val EXTRA_BRIGHTNESS  = "brightness"
        const val EXTRA_FRAME_SKIP  = "frame_skip"
        const val EXTRA_SMOOTHING   = "smoothing"
        const val EXTRA_ZONE_WIDTH  = "zone_width"
        // Effect extras (also used in updateEffect channel call)
        const val EXTRA_EFFECT_MODE    = "mode"
        const val EXTRA_PRIMARY_COLOR  = "primaryColor"
        const val EXTRA_SECONDARY_COLOR = "secondaryColor"
        const val EXTRA_SPEED          = "speed"
        const val EXTRA_DUTY_CYCLE     = "dutyCycle"
        const val EXTRA_MIRROR_SIDES   = "mirrorSides"
        const val EXTRA_CYCLE_COLORS   = "cycleColors"

        // ── Effect mode names (must match Dart LedEffectMode.name) ────────
        const val MODE_AMBIENT_SYNC  = "ambientSync"
        const val MODE_SOLID_COLOR   = "solidColor"
        const val MODE_SPLIT_COLOR   = "splitColor"
        const val MODE_BREATHING     = "breathing"
        const val MODE_STROBE        = "strobe"
        const val MODE_RAINBOW       = "rainbow"
        const val MODE_COLOR_CYCLE   = "colorCycle"

        @Volatile var isRunning = false
            private set

        @Volatile var instance: LightmeupService? = null
            private set

        @Volatile var colorSink: EventChannel.EventSink? = null

        private const val COLOR_PUSH_INTERVAL_MS = 66L
        @Volatile private var lastPushMs = 0L
    }

    // ── Settings ───────────────────────────────────────────────────────────
    @Volatile private var brightness    = 0.6f
    @Volatile private var frameSkip     = 1
    @Volatile private var smoothing     = 0.35f
    @Volatile private var zoneWidth     = 0.15f

    // ── Effect state ───────────────────────────────────────────────────────
    @Volatile private var effectMode    = MODE_AMBIENT_SYNC
    @Volatile private var primaryColor  = Color.WHITE
    @Volatile private var secondaryColor = Color.argb(255, 155, 107, 255)  // violet
    @Volatile private var effectSpeed   = 0.5f
    @Volatile private var dutyCycle     = 0.5f
    @Volatile private var mirrorSides   = true
    @Volatile private var cycleColors   = intArrayOf(
        Color.argb(255, 0, 212, 255),
        Color.argb(255, 155, 107, 255),
        Color.argb(255, 0, 255, 136),
        Color.argb(255, 255, 68, 102)
    )

    // ── Effect animation clocks ────────────────────────────────────────────
    private var effectStartMs    = 0L
    private var lastStrobeSate   = false
    private var colorCycleIndex  = 0
    private var colorCycleMs     = 0L

    // ── Capture state ──────────────────────────────────────────────────────
    @Volatile private var isCapturing = false
    private var frameCounter    = 0
    private var framesProcessed = 0
    private var framesDropped   = 0

    private var smoothedLeft  = Color.BLACK
    private var smoothedRight = Color.BLACK

    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var projectionManager: MediaProjectionManager
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay?   = null
    private var imageReader: ImageReader?         = null

    // Capture runs on its own thread; effect-only loop shares it.
    private val captureThread = HandlerThread("LightMeUpCapture").also { it.start() }
    private val captureHandler = Handler(captureThread.looper)

    // Effect-only loop tick (used when not in ambientSync mode).
    private val effectRunnable = object : Runnable {
        override fun run() {
            if (!isRunning || effectMode == MODE_AMBIENT_SYNC) return
            val (left, right) = computeEffect()
            pushColors(left, right)
            ledController.setZoneColors(left, right)
            captureHandler.postDelayed(this, 33L) // ~30 fps
        }
    }

    private lateinit var ledController: RetroidLEDController

    // ── Lifecycle ──────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        instance = this
        projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        ledController = RetroidLEDController(applicationContext)
        createNotificationChannel()
        Log.i(TAG, "onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand")
        if (intent == null) { stopSelf(); return START_NOT_STICKY }

        brightness  = intent.getFloatExtra(EXTRA_BRIGHTNESS, 0.6f)
        frameSkip   = intent.getIntExtra(EXTRA_FRAME_SKIP, 1)
        smoothing   = intent.getFloatExtra(EXTRA_SMOOTHING, 0.35f)
        zoneWidth   = intent.getFloatExtra(EXTRA_ZONE_WIDTH, 0.15f)

        applyEffectExtras(intent)

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        val data       = intent.getParcelableExtra<Intent>(EXTRA_DATA)

        if (data == null) { stopSelf(); return START_NOT_STICKY }

        startForeground(NOTIF_ID, buildNotification())

        ledController.setBrightness(brightness)
        ledController.setEnabled(true)

        frameCounter    = 0
        framesProcessed = 0
        framesDropped   = 0
        lastPushMs      = 0L
        effectStartMs   = SystemClock.elapsedRealtime()
        ColorSampler.reset()

        if (effectMode == MODE_AMBIENT_SYNC) {
            startCapture(resultCode, data)
        } else {
            // Store projection data in case user switches to ambient later,
            // but start the effect loop immediately.
            startCapture(resultCode, data)   // still needed for future ambient switch
            startEffectLoop()
        }

        isRunning = true
        Log.i(TAG, "Service running, mode=$effectMode")
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        captureHandler.removeCallbacks(effectRunnable)
        stopCapture()
        ledController.restore()
        pushColors(Color.BLACK, Color.BLACK)
        isRunning = false
        instance  = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Live updates from Flutter ──────────────────────────────────────────

    fun updateSettings(b: Float, fs: Int, sm: Float, zw: Float) {
        brightness = b; frameSkip = fs; smoothing = sm; zoneWidth = zw
        ledController.setBrightness(b)
        Log.d(TAG, "updateSettings: brightness=$b fs=$fs sm=$sm zw=$zw")
    }

    /**
     * Called by MainActivity when Flutter calls the 'updateEffect' method channel.
     */
    fun updateEffect(args: Map<String, Any?>) {
        val newMode = args["mode"] as? String ?: effectMode
        val modeChanged = newMode != effectMode
        effectMode = newMode
        applyEffectArgs(args)

        if (modeChanged) {
            // Only reset animation clocks when the mode itself changes.
            // Resetting on every config tweak (e.g. speed slider drag) would
            // cause breathing/strobe to restart from phase 0 on each update,
            // which looks like the speed change had no effect.
            effectStartMs   = SystemClock.elapsedRealtime()
            colorCycleMs    = SystemClock.elapsedRealtime()
            colorCycleIndex = 0
        }

        Log.d(TAG, "updateEffect: mode=$effectMode modeChanged=$modeChanged")

        if (effectMode == MODE_AMBIENT_SYNC) {
            captureHandler.removeCallbacks(effectRunnable)
        } else if (modeChanged) {
            // Only restart the loop (which resets effectStartMs again) when
            // the mode changed. For config-only updates the loop is already
            // running and picks up the new values automatically.
            startEffectLoop()
        }
    }

    // ── Effect computation ─────────────────────────────────────────────────

    /**
     * Compute the current left/right colours from the active static effect.
     * Called at ~30 fps from the effect loop (not on the UI thread).
     */
    private fun computeEffect(): Pair<Int, Int> {
        val now   = SystemClock.elapsedRealtime()
        val elapsedMs = now - effectStartMs

        return when (effectMode) {

            MODE_SOLID_COLOR -> {
                val c = ledController.boostSaturation(primaryColor, brightness = brightness)
                Pair(c, c)
            }

            MODE_SPLIT_COLOR -> {
                val l = ledController.boostSaturation(primaryColor,   brightness = brightness)
                val r = ledController.boostSaturation(secondaryColor, brightness = brightness)
                Pair(l, r)
            }

            MODE_BREATHING -> {
                // Period: speed 0.05 → ~8 s, speed 1.0 → ~0.4 s
                val periodMs = (8000f / (effectSpeed * 8f + 1f)).toLong().coerceAtLeast(400L)
                val phase    = (elapsedMs % periodMs).toFloat() / periodMs
                // sine curve: 0→1→0
                val sine = (sin(phase * 2.0 * PI - PI / 2.0) * 0.5 + 0.5).toFloat()

                val hsv = FloatArray(3)
                Color.colorToHSV(primaryColor, hsv)
                hsv[2] = (hsv[2] * sine * brightness).coerceIn(0f, 1f)
                val c = Color.HSVToColor(hsv)

                if (mirrorSides) {
                    Pair(c, c)
                } else {
                    // Right stick offset by half a phase
                    val phase2 = ((elapsedMs + periodMs / 2) % periodMs).toFloat() / periodMs
                    val sine2  = (sin(phase2 * 2.0 * PI - PI / 2.0) * 0.5 + 0.5).toFloat()
                    hsv[2] = (FloatArray(3).also { Color.colorToHSV(primaryColor, it) }[2] * sine2 * brightness).coerceIn(0f, 1f)
                    Pair(c, Color.HSVToColor(hsv))
                }
            }

            MODE_STROBE -> {
                // Flash frequency: speed 0.05 → 1 Hz, speed 1.0 → 20 Hz
                val freqHz   = effectSpeed * 19f + 1f
                val periodMs = (1000f / freqHz).toLong()
                val phase    = (elapsedMs % periodMs).toFloat() / periodMs
                val on = phase < dutyCycle
                val c = if (on)
                    ledController.boostSaturation(primaryColor, brightness = brightness)
                else Color.BLACK
                Pair(c, c)
            }

            MODE_RAINBOW -> {
                // Full hue cycle: speed 0.05 → ~20 s, speed 1.0 → ~1 s
                val periodMs = (20000f / (effectSpeed * 9f + 1f)).toLong().coerceAtLeast(1000L)
                val hue = ((elapsedMs % periodMs).toFloat() / periodMs) * 360f
                val hsv = floatArrayOf(hue, 1f, brightness)
                val cL = Color.HSVToColor(hsv)
                // Right stick offset by 30° for a split-rainbow look
                val hsvR = floatArrayOf((hue + 30f) % 360f, 1f, brightness)
                val cR = Color.HSVToColor(hsvR)
                Pair(cL, cR)
            }

            MODE_COLOR_CYCLE -> {
                if (cycleColors.isEmpty()) return Pair(Color.BLACK, Color.BLACK)

                val fadeMs = (4000f / (effectSpeed * 8f + 1f)).toLong().coerceAtLeast(200L)
                val n      = cycleColors.size

                val elapsed   = now - effectStartMs
                val stepIndex = (elapsed / fadeMs).toInt()
                val phase     = elapsed % fadeMs

                val fromColor = cycleColors[stepIndex % n]
                val toColor   = cycleColors[(stepIndex + 1) % n]

                val t = (phase.toFloat() / fadeMs).coerceIn(0f, 1f)
                Pair(lerpColor(fromColor, toColor, t), lerpColor(fromColor, toColor, t))
            }

            else -> Pair(Color.BLACK, Color.BLACK)
        }
    }

    // ── Effect loop (non-ambient modes) ────────────────────────────────────

    private fun startEffectLoop() {
        captureHandler.removeCallbacks(effectRunnable)
        captureHandler.post(effectRunnable)
        Log.d(TAG, "Effect loop started for mode=$effectMode")
    }

    // ── Capture ────────────────────────────────────────────────────────────

    private fun startCapture(resultCode: Int, data: Intent) {
        mediaProjection = projectionManager.getMediaProjection(resultCode, data)
        if (mediaProjection == null) { stopSelf(); return }

        imageReader = ImageReader.newInstance(CAPTURE_W, CAPTURE_H, PixelFormat.RGBA_8888, 2)
        imageReader!!.setOnImageAvailableListener({ reader -> onFrameAvailable(reader) }, captureHandler)

        val density = resources.displayMetrics.densityDpi
        virtualDisplay = mediaProjection!!.createVirtualDisplay(
            "LightMeUpCapture",
            CAPTURE_W, CAPTURE_H, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, null
        )
        isCapturing = true
        Log.i(TAG, "VirtualDisplay: ${CAPTURE_W}x${CAPTURE_H}")
    }

    private fun onFrameAvailable(reader: ImageReader) {
        // Only do pixel work when in ambient mode.
        if (effectMode != MODE_AMBIENT_SYNC) {
            reader.acquireLatestImage()?.close()
            return
        }

        frameCounter++
        if (frameCounter % (frameSkip + 1) != 0) {
            reader.acquireLatestImage()?.close()
            framesDropped++
            return
        }

        val image = reader.acquireLatestImage() ?: return
        if (!isCapturing) { image.close(); return }

        try {
            val plane  = image.planes[0]
            val buffer = plane.buffer
            val pw     = plane.rowStride / plane.pixelStride

            val bitmap = Bitmap.createBitmap(pw, image.height, Bitmap.Config.ARGB_8888)
            bitmap.copyPixelsFromBuffer(buffer)

            val cropped = if (pw != CAPTURE_W)
                Bitmap.createBitmap(bitmap, 0, 0, CAPTURE_W, CAPTURE_H)
            else bitmap

            val (leftColor, rightColor) = ColorSampler.sample(cropped, zoneWidth, smoothing = 0f)

            val alpha = 0.25f
            smoothedLeft  = lerpColor(smoothedLeft,  leftColor,  alpha)
            smoothedRight = lerpColor(smoothedRight, rightColor, alpha)

            val leftLuma  = Color.red(smoothedLeft)  * 0.299 + Color.green(smoothedLeft)  * 0.587 + Color.blue(smoothedLeft)  * 0.114
            val rightLuma = Color.red(smoothedRight) * 0.299 + Color.green(smoothedRight) * 0.587 + Color.blue(smoothedRight) * 0.114
            val avgLuma   = (leftLuma + rightLuma) / 2.0

            val finalLeft: Int
            val finalRight: Int

            if (avgLuma < 8.0) {
                finalLeft  = Color.BLACK
                finalRight = Color.BLACK
                ledController.setZoneColors(Color.BLACK, Color.BLACK)
            } else {
                finalLeft  = ledController.boostSaturation(smoothedLeft,  brightness = brightness)
                finalRight = ledController.boostSaturation(smoothedRight, brightness = brightness)
                ledController.setZoneColors(finalLeft, finalRight)
            }

            val now = SystemClock.elapsedRealtime()
            if (now - lastPushMs >= COLOR_PUSH_INTERVAL_MS) {
                lastPushMs = now
                pushColors(finalLeft, finalRight)
            }

            framesProcessed++

            if (cropped !== bitmap) cropped.recycle()
            bitmap.recycle()

        } catch (e: Exception) {
            Log.e(TAG, "Frame error: ${e.message}", e)
        } finally {
            image.close()
        }
    }

    // ── EventChannel push ──────────────────────────────────────────────────

    private fun pushColors(left: Int, right: Int) {
        val sink = colorSink ?: return
        val fl = (left  and 0x00FFFFFF) or 0xFF000000.toInt()
        val fr = (right and 0x00FFFFFF) or 0xFF000000.toInt()
        mainHandler.post {
            sink.success(mapOf("left" to fl, "right" to fr))
        }
    }

    private fun stopCapture() {
        isCapturing = false
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
        virtualDisplay  = null
        imageReader     = null
        mediaProjection = null
        captureThread.quitSafely()
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private fun lerpColor(from: Int, to: Int, alpha: Float): Int {
        val r = (Color.red(from)   + (Color.red(to)   - Color.red(from))   * alpha).toInt().coerceIn(0, 255)
        val g = (Color.green(from) + (Color.green(to) - Color.green(from)) * alpha).toInt().coerceIn(0, 255)
        val b = (Color.blue(from)  + (Color.blue(to)  - Color.blue(from))  * alpha).toInt().coerceIn(0, 255)
        return Color.rgb(r, g, b)
    }

    /**
     * Parse effect parameters from a start intent.
     */
    private fun applyEffectExtras(intent: Intent) {
        effectMode    = intent.getStringExtra(EXTRA_EFFECT_MODE) ?: MODE_AMBIENT_SYNC
        primaryColor  = intent.getIntExtra(EXTRA_PRIMARY_COLOR,  Color.WHITE)
        secondaryColor = intent.getIntExtra(EXTRA_SECONDARY_COLOR, Color.argb(255, 155, 107, 255))
        effectSpeed   = intent.getFloatExtra(EXTRA_SPEED, 0.5f)
        dutyCycle     = intent.getFloatExtra(EXTRA_DUTY_CYCLE, 0.5f)
        mirrorSides   = intent.getBooleanExtra(EXTRA_MIRROR_SIDES, true)
        @Suppress("UNCHECKED_CAST")
        val raw = intent.getSerializableExtra(EXTRA_CYCLE_COLORS) as? ArrayList<Int>
        if (raw != null && raw.isNotEmpty()) cycleColors = raw.toIntArray()
    }

    /**
     * Parse effect parameters from a MethodChannel map (updateEffect).
     */
    private fun applyEffectArgs(args: Map<String, Any?>) {
        // Flutter MethodChannel sends Dart ints as Long on the Kotlin side,
        // so `as? Int` always returns null for color values. Cast via Long first.
        args[EXTRA_PRIMARY_COLOR]?.let   { primaryColor   = (it as? Long)?.toInt() ?: it as? Int ?: primaryColor }
        args[EXTRA_SECONDARY_COLOR]?.let { secondaryColor = (it as? Long)?.toInt() ?: it as? Int ?: secondaryColor }
        (args[EXTRA_SPEED]           as? Double)?.let { effectSpeed  = it.toFloat() }
        (args[EXTRA_DUTY_CYCLE]      as? Double)?.let { dutyCycle    = it.toFloat() }
        (args[EXTRA_MIRROR_SIDES]    as? Boolean)?.let { mirrorSides = it }
        @Suppress("UNCHECKED_CAST")
        val rawCycle = args[EXTRA_CYCLE_COLORS] as? List<*>
        if (rawCycle != null && rawCycle.isNotEmpty()) {
            // Each element may arrive as Long or Int depending on the channel codec.
            cycleColors = rawCycle.mapNotNull { e ->
                (e as? Long)?.toInt() ?: e as? Int
            }.toIntArray()
        }
    }

    // ── Notification ───────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID, "LightMeUp Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "LED sync running" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("LightMeUp")
            .setContentText("LED sync active")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }
}