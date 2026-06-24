package com.example.lightmeup

// MainActivity.kt — complete replacement
//
// Changes vs original:
//   • requestOverlayPermission / overlayPermissionLauncher — handles
//     Settings.ACTION_MANAGE_OVERLAY_PERMISSION flow.
//   • "startOverlay"  — checks SYSTEM_ALERT_WINDOW, then starts OverlayService.
//   • "stopOverlay"   — stops OverlayService.
//   • "setOverlayFocusable" — forwards focus-mode toggle to OverlayService.
//   • "isOverlayRunning"    — returns OverlayService.isRunning.
//   • "isOverlayPermissionGranted" — returns Settings.canDrawOverlays().
//   All original calls (startService, stopService, updateSettings, isRunning)
//   are unchanged.

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
        private const val TAG            = "MainActivity"
        private const val METHOD_CHANNEL = "com.example.lightmeup/lightmeup"
        private const val EVENT_CHANNEL  = "com.example.lightmeup/colors"
    }

    private lateinit var projectionManager: MediaProjectionManager

    // Pending state for the normal LightmeupService start flow.
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBrightness = 0.6f
    private var pendingFrameSkip  = 1
    private var pendingSmoothing  = 0.35f
    private var pendingZoneWidth  = 0.15f

    // Pending result for the overlay-permission request.
    private var pendingOverlayResult: MethodChannel.Result? = null

    // ── Activity-result launchers ──────────────────────────────────────────

    /** WRITE_SETTINGS — needed before MediaProjection for LED brightness. */
    private val writeSettingsLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { _: ActivityResult ->
        if (Settings.System.canWrite(this)) {
            Log.i(TAG, "WRITE_SETTINGS granted")
            requestProjectionPermission()
        } else {
            Log.e(TAG, "WRITE_SETTINGS denied")
            pendingResult?.success(false)
            pendingResult = null
        }
    }

    /** MediaProjection permission — starts LightmeupService on grant. */
    private val projectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result: ActivityResult ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            Log.i(TAG, "MediaProjection granted")
            val serviceIntent = Intent(this, LightmeupService::class.java).apply {
                putExtra(LightmeupService.EXTRA_RESULT_CODE, result.resultCode)
                putExtra(LightmeupService.EXTRA_DATA,        result.data)
                putExtra(LightmeupService.EXTRA_BRIGHTNESS,  pendingBrightness)
                putExtra(LightmeupService.EXTRA_FRAME_SKIP,  pendingFrameSkip)
                putExtra(LightmeupService.EXTRA_SMOOTHING,   pendingSmoothing)
                putExtra(LightmeupService.EXTRA_ZONE_WIDTH,  pendingZoneWidth)
            }
            startForegroundService(serviceIntent)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                pendingResult?.success(LightmeupService.isRunning)
                pendingResult = null
            }, 500)
        } else {
            Log.e(TAG, "MediaProjection denied (resultCode=${result.resultCode})")
            pendingResult?.success(false)
            pendingResult = null
        }
    }

    /**
     * SYSTEM_ALERT_WINDOW (overlay) permission.
     * Android sends the user to a settings page; we get a callback when they
     * return — at that point we re-check canDrawOverlays() and either start
     * the service or report failure.
     */
    private val overlayPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { _: ActivityResult ->
        if (Settings.canDrawOverlays(this)) {
            Log.i(TAG, "SYSTEM_ALERT_WINDOW granted — starting OverlayService")
            startForegroundService(Intent(this, OverlayService::class.java))
            pendingOverlayResult?.success(true)
        } else {
            Log.e(TAG, "SYSTEM_ALERT_WINDOW denied by user")
            pendingOverlayResult?.success(false)
        }
        pendingOverlayResult = null
    }

    // ── Flutter engine configuration ───────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pendingResult = null

        projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager

        // ── MethodChannel ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── LightmeupService (unchanged) ───────────────────────

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
                        pendingFrameSkip  =  call.argument<Int>("frameSkip")    ?: 1
                        pendingSmoothing  = (call.argument<Double>("smoothing")  ?: 0.35).toFloat()
                        pendingZoneWidth  = (call.argument<Double>("zoneWidth")  ?: 0.15).toFloat()
                        pendingResult     = result

                        if (!Settings.System.canWrite(this)) {
                            Log.d(TAG, "Launching WRITE_SETTINGS request")
                            writeSettingsLauncher.launch(
                                Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS,
                                    Uri.parse("package:$packageName"))
                            )
                        } else {
                            requestProjectionPermission()
                        }
                    }

                    "stopService" -> {
                        Log.d(TAG, "stopService called")
                        stopService(Intent(this, LightmeupService::class.java))
                        android.os.Handler(android.os.Looper.getMainLooper())
                            .postDelayed({ result.success(null) }, 300)
                    }

                    "updateSettings" -> {
                        val b  = (call.argument<Double>("brightness") ?: 0.6).toFloat()
                        val fs =  call.argument<Int>("frameSkip")    ?: 1
                        val sm = (call.argument<Double>("smoothing")  ?: 0.35).toFloat()
                        val zw = (call.argument<Double>("zoneWidth")  ?: 0.15).toFloat()
                        LightmeupService.instance?.updateSettings(b, fs, sm, zw)
                            ?: Log.d(TAG, "updateSettings: service not running")
                        result.success(null)
                    }

                    "isRunning" -> {
                        val running = LightmeupService.isRunning
                        Log.d(TAG, "isRunning: $running")
                        result.success(running)
                    }

                    // ── OverlayService ─────────────────────────────────────

                    /**
                     * Start the system-overlay window.
                     * If SYSTEM_ALERT_WINDOW is not yet granted, opens the
                     * permission settings page and resolves asynchronously.
                     * Returns true on success, false if permission denied.
                     */
                    "startOverlay" -> {
                        if (OverlayService.isRunning) {
                            Log.d(TAG, "startOverlay: already running")
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (Settings.canDrawOverlays(this)) {
                            Log.d(TAG, "startOverlay: permission OK")
                            startForegroundService(Intent(this, OverlayService::class.java))
                            result.success(true)
                        } else {
                            Log.d(TAG, "startOverlay: requesting SYSTEM_ALERT_WINDOW")
                            pendingOverlayResult = result
                            overlayPermissionLauncher.launch(
                                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName"))
                            )
                            // result is resolved inside overlayPermissionLauncher callback
                        }
                    }

                    /** Stop the overlay window. */
                    "stopOverlay" -> {
                        Log.d(TAG, "stopOverlay called")
                        stopService(Intent(this, OverlayService::class.java))
                        result.success(null)
                    }

                    /**
                     * Toggle whether the overlay window intercepts input.
                     * Pass focusable=true when a panel slides open so it can
                     * receive touches and hardware keys; false when closed so
                     * the underlying app gets input as normal.
                     */
                    "setOverlayFocusable" -> {
                        val focusable = call.argument<Boolean>("focusable") ?: false
                        OverlayService.instance?.setFocusable(focusable)
                            ?: Log.d(TAG, "setOverlayFocusable: service not running")
                        result.success(null)
                    }

                    /** Whether the overlay window is currently showing. */
                    "isOverlayRunning" -> result.success(OverlayService.isRunning)

                    /** Whether SYSTEM_ALERT_WINDOW permission is granted. */
                    "isOverlayPermissionGranted" ->
                        result.success(Settings.canDrawOverlays(this))

                    else -> result.notImplemented()
                }
            }

        // ── EventChannel — streams LED colours to Flutter ──────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    Log.i(TAG, "EventChannel: Flutter listening for colours")
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