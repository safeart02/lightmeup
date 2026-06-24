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

class LightmeupService : Service() {

    companion object {
        private const val TAG      = "LightmeupService"
        private const val NOTIF_ID = 1001
        private const val CHANNEL_ID = "lightmeup_channel"

        private const val CAPTURE_W = 160
        private const val CAPTURE_H = 90

        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_DATA        = "data"
        const val EXTRA_BRIGHTNESS  = "brightness"
        const val EXTRA_FRAME_SKIP  = "frame_skip"
        const val EXTRA_SMOOTHING   = "smoothing"
        const val EXTRA_ZONE_WIDTH  = "zone_width"

        @Volatile var isRunning = false
            private set

        @Volatile var instance: LightmeupService? = null
            private set

        // ── EventChannel sink — set by MainActivity, nulled on stop ───────
        // Volatile so the capture HandlerThread sees writes from the main thread.
        @Volatile var colorSink: EventChannel.EventSink? = null

        // Throttle: only push a colour event every ~66 ms (~15 fps).
        private const val COLOR_PUSH_INTERVAL_MS = 66L
        @Volatile private var lastPushMs = 0L
    }

    @Volatile private var brightness = 0.6f
    @Volatile private var frameSkip  = 1
    @Volatile private var smoothing  = 0.35f
    @Volatile private var zoneWidth  = 0.15f
    @Volatile private var isCapturing = false

    private var frameCounter    = 0
    private var framesProcessed = 0
    private var framesDropped   = 0

    private var smoothedLeft  = Color.BLACK
    private var smoothedRight = Color.BLACK

    // Main-thread handler — used to post EventSink calls safely.
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var projectionManager: MediaProjectionManager
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay?   = null
    private var imageReader: ImageReader?         = null
    private val handlerThread = HandlerThread("LightMeUpCapture").also { it.start() }
    private val handler = Handler(handlerThread.looper)

    private lateinit var ledController: RetroidLEDController

    // ── Lifecycle ──────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        instance = this
        projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE)
            as MediaProjectionManager
        ledController = RetroidLEDController(applicationContext)
        createNotificationChannel()
        Log.i(TAG, "onCreate — service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand called")

        if (intent == null) {
            Log.e(TAG, "onStartCommand: null intent — stopping")
            return START_NOT_STICKY
        }

        brightness = intent.getFloatExtra(EXTRA_BRIGHTNESS, 0.6f)
        frameSkip  = intent.getIntExtra(EXTRA_FRAME_SKIP, 1)
        smoothing  = intent.getFloatExtra(EXTRA_SMOOTHING, 0.35f)
        zoneWidth  = intent.getFloatExtra(EXTRA_ZONE_WIDTH, 0.15f)

        Log.d(TAG, "Settings: brightness=$brightness, frameSkip=$frameSkip, " +
                   "smoothing=$smoothing, zoneWidth=$zoneWidth")

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        val data       = intent.getParcelableExtra<Intent>(EXTRA_DATA)

        if (data == null) {
            Log.e(TAG, "No MediaProjection data in intent — stopping self")
            stopSelf()
            return START_NOT_STICKY
        }

        val hasSecureWrite = checkSelfPermission(
            "android.permission.WRITE_SECURE_SETTINGS"
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasSecureWrite) {
            Log.w(TAG, "WRITE_SECURE_SETTINGS not granted — LED control via " +
                       "Settings.Secure will fail silently.")
        }

        startForeground(NOTIF_ID, buildNotification())
        Log.i(TAG, "Foreground service started")

        ledController.setBrightness(brightness)
        ledController.setEnabled(true)

        frameCounter    = 0
        framesProcessed = 0
        framesDropped   = 0
        lastPushMs      = 0L
        ColorSampler.reset()

        startCapture(resultCode, data)
        isRunning = true
        Log.i(TAG, "Service is now running")

        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy — processed=$framesProcessed dropped=$framesDropped")
        stopCapture()
        ledController.restore()
        // Push black to the panel before disconnecting so it doesn't freeze
        // on the last colour when the service stops.
        pushColors(Color.BLACK, Color.BLACK)
        isRunning = false
        instance  = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Live settings update ───────────────────────────────────────────────

    fun updateSettings(b: Float, fs: Int, sm: Float, zw: Float) {
        Log.d(TAG, "updateSettings: brightness=$b, frameSkip=$fs, " +
                   "smoothing=$sm, zoneWidth=$zw")
        brightness = b
        frameSkip  = fs
        smoothing  = sm
        zoneWidth  = zw
        ledController.setBrightness(b)
    }

    // ── Capture ────────────────────────────────────────────────────────────

    private fun startCapture(resultCode: Int, data: Intent) {
        Log.i(TAG, "startCapture: creating MediaProjection")
        mediaProjection = projectionManager.getMediaProjection(resultCode, data)

        if (mediaProjection == null) {
            Log.e(TAG, "getMediaProjection returned null!")
            stopSelf()
            return
        }

        imageReader = ImageReader.newInstance(
            CAPTURE_W, CAPTURE_H, PixelFormat.RGBA_8888, 2
        )
        imageReader!!.setOnImageAvailableListener({ reader ->
            onFrameAvailable(reader)
        }, handler)

        val density = resources.displayMetrics.densityDpi
        virtualDisplay = mediaProjection!!.createVirtualDisplay(
            "LightMeUpCapture",
            CAPTURE_W, CAPTURE_H, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, null
        )
        isCapturing = true

        Log.i(TAG, "VirtualDisplay created: ${CAPTURE_W}x${CAPTURE_H} @ ${density}dpi")
    }

    private fun onFrameAvailable(reader: ImageReader) {
        frameCounter++

        if (frameCounter % (frameSkip + 1) != 0) {
            reader.acquireLatestImage()?.close()
            framesDropped++
            return
        }

        val image = reader.acquireLatestImage()
        if (image == null) {
            Log.w(TAG, "acquireLatestImage returned null (frame $frameCounter)")
            return
        }
        if (!isCapturing) {
            image.close()
            return
        }

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

            val alpha = 0.6f
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

            // ── Push to Flutter panel (throttled to ~15 fps) ───────────────
            val now = SystemClock.elapsedRealtime()
            if (now - lastPushMs >= COLOR_PUSH_INTERVAL_MS) {
                lastPushMs = now
                pushColors(finalLeft, finalRight)
            }

            framesProcessed++

            if (framesProcessed % 100 == 0) {
                Log.d(TAG, "Heartbeat: processed=$framesProcessed " +
                           "dropped=$framesDropped total=$frameCounter")
            }

            if (cropped !== bitmap) cropped.recycle()
            bitmap.recycle()

        } catch (e: Exception) {
            Log.e(TAG, "Frame processing error at frame $frameCounter: ${e.message}", e)
        } finally {
            image.close()
        }
    }

    // ── EventChannel push ──────────────────────────────────────────────────

    /// Pushes left/right colours to Flutter. Always called on the main thread
    /// because EventSink is not thread-safe.
    private fun pushColors(left: Int, right: Int) {
        val sink = colorSink ?: return
        // Convert Android Color int (0xAARRGGBB) to Flutter Color int (0xAARRGGBB) — same format.
        // Ensure full alpha so Flutter's Color() constructor renders it opaque.
        val flutterLeft  = (left  and 0x00FFFFFF) or 0xFF000000.toInt()
        val flutterRight = (right and 0x00FFFFFF) or 0xFF000000.toInt()
        mainHandler.post {
            sink.success(mapOf("left" to flutterLeft, "right" to flutterRight))
        }
    }

    private fun stopCapture() {
        isCapturing = false
        Log.i(TAG, "stopCapture")
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
        virtualDisplay  = null
        imageReader     = null
        mediaProjection = null
        handlerThread.quitSafely()
    }

    private fun lerpColor(from: Int, to: Int, alpha: Float): Int {
        val r = (Color.red(from)   + (Color.red(to)   - Color.red(from))   * alpha).toInt().coerceIn(0, 255)
        val g = (Color.green(from) + (Color.green(to) - Color.green(from)) * alpha).toInt().coerceIn(0, 255)
        val b = (Color.blue(from)  + (Color.blue(to)  - Color.blue(from))  * alpha).toInt().coerceIn(0, 255)
        return Color.rgb(r, g, b)
    }

    // ── Notification ───────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID, "LightMeUp Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "LED sync running" }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
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