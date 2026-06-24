package com.example.lightmeup

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.provider.Settings
import android.util.Log
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG           = "MainActivity"
        private const val METHOD_CHANNEL = "com.example.lightmeup/lightmeup"
        private const val EVENT_CHANNEL  = "com.example.lightmeup/colors"
    }

    private lateinit var projectionManager: MediaProjectionManager

    private var pendingResult: MethodChannel.Result? = null
    private var pendingBrightness = 0.6f
    private var pendingFrameSkip  = 1
    private var pendingSmoothing  = 0.35f
    private var pendingZoneWidth  = 0.15f

    // ── Activity Result Launchers ─────────────────────────────────────────

    private val writeSettingsLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { _: ActivityResult ->
        if (Settings.System.canWrite(this)) {
            Log.i(TAG, "WRITE_SETTINGS granted")
            requestProjectionPermission()
        } else {
            Log.e(TAG, "WRITE_SETTINGS denied by user")
            pendingResult?.success(false)
            pendingResult = null
        }
    }

    private val projectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result: ActivityResult ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            Log.i(TAG, "MediaProjection permission granted")
            val serviceIntent = Intent(this, LightmeupService::class.java).apply {
                putExtra(LightmeupService.EXTRA_RESULT_CODE, result.resultCode)
                putExtra(LightmeupService.EXTRA_DATA, result.data)
                putExtra(LightmeupService.EXTRA_BRIGHTNESS, pendingBrightness)
                putExtra(LightmeupService.EXTRA_FRAME_SKIP, pendingFrameSkip)
                putExtra(LightmeupService.EXTRA_SMOOTHING, pendingSmoothing)
                putExtra(LightmeupService.EXTRA_ZONE_WIDTH, pendingZoneWidth)
            }
            startForegroundService(serviceIntent)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                pendingResult?.success(LightmeupService.isRunning)
                pendingResult = null
            }, 500)
            return@registerForActivityResult
        } else {
            Log.e(TAG, "MediaProjection denied (resultCode=${result.resultCode})")
            pendingResult?.success(false)
        }
        pendingResult = null
    }

    // ── Flutter Engine ─────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pendingResult = null

        projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE)
            as MediaProjectionManager

        // ── MethodChannel (unchanged) ──────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startService" -> {
                        if (LightmeupService.isRunning) {
                            Log.d(TAG, "startService: already running")
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        if (pendingResult != null) {
                            Log.w(TAG, "Dropping stale pendingResult")
                            pendingResult = null
                        }

                        pendingBrightness = (call.argument<Double>("brightness") ?: 0.6).toFloat()
                        pendingFrameSkip  = call.argument<Int>("frameSkip") ?: 1
                        pendingSmoothing  = (call.argument<Double>("smoothing") ?: 0.35).toFloat()
                        pendingZoneWidth  = (call.argument<Double>("zoneWidth") ?: 0.15).toFloat()
                        pendingResult     = result

                        if (!Settings.System.canWrite(this)) {
                            Log.d(TAG, "Launching WRITE_SETTINGS request")
                            writeSettingsLauncher.launch(
                                Intent(
                                    Settings.ACTION_MANAGE_WRITE_SETTINGS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        } else {
                            Log.d(TAG, "WRITE_SETTINGS OK, launching projection request")
                            requestProjectionPermission()
                        }
                    }

                    "stopService" -> {
                        Log.d(TAG, "stopService called")
                        stopService(Intent(this, LightmeupService::class.java))
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            result.success(null)
                        }, 300)
                    }

                    "updateSettings" -> {
                        val b  = (call.argument<Double>("brightness") ?: 0.6).toFloat()
                        val fs = call.argument<Int>("frameSkip") ?: 1
                        val sm = (call.argument<Double>("smoothing") ?: 0.35).toFloat()
                        val zw = (call.argument<Double>("zoneWidth") ?: 0.15).toFloat()
                        LightmeupService.instance?.updateSettings(b, fs, sm, zw)
                            ?: Log.d(TAG, "updateSettings: service not running")
                        result.success(null)
                    }

                    "isRunning" -> {
                        val running = LightmeupService.isRunning
                        Log.d(TAG, "isRunning: $running")
                        result.success(running)
                    }

                    else -> result.notImplemented()
                }
            }

        // ── EventChannel — streams LED colours to Flutter ──────────────────
        // The sink is stored on LightmeupService.colorSink so the capture
        // thread (via mainHandler.post) can reach it without a circular ref.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    Log.i(TAG, "EventChannel: Flutter is listening for colours")
                    LightmeupService.colorSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    Log.i(TAG, "EventChannel: Flutter cancelled colour stream")
                    LightmeupService.colorSink = null
                }
            })
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private fun requestProjectionPermission() {
        Log.d(TAG, "Launching screen capture intent")
        projectionLauncher.launch(projectionManager.createScreenCaptureIntent())
    }
}