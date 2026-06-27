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
        private const val TAG            = "MainActivity"
        private const val METHOD_CHANNEL = "com.example.lightmeup/lightmeup"
        private const val EVENT_CHANNEL  = "com.example.lightmeup/colors"
    }

    private lateinit var projectionManager: MediaProjectionManager

    private var pendingResult: MethodChannel.Result? = null
    private var pendingBrightness  = 0.6f
    private var pendingFrameSkip   = 1
    private var pendingSmoothing   = 0.35f
    private var pendingZoneWidth   = 0.15f

    // Cached pending effect map so we can forward it in the start intent.
    private var pendingEffectArgs: Map<String, Any?> = emptyMap()

    // ── Activity Result Launchers ──────────────────────────────────────────

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

    private val projectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result: ActivityResult ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            Log.i(TAG, "MediaProjection granted")
            val si = Intent(this, LightmeupService::class.java).apply {
                putExtra(LightmeupService.EXTRA_RESULT_CODE, result.resultCode)
                putExtra(LightmeupService.EXTRA_DATA, result.data)
                putExtra(LightmeupService.EXTRA_BRIGHTNESS, pendingBrightness)
                putExtra(LightmeupService.EXTRA_FRAME_SKIP, pendingFrameSkip)
                putExtra(LightmeupService.EXTRA_SMOOTHING,  pendingSmoothing)
                putExtra(LightmeupService.EXTRA_ZONE_WIDTH, pendingZoneWidth)

                // Forward effect parameters
                putExtra(LightmeupService.EXTRA_EFFECT_MODE,
                    pendingEffectArgs["mode"] as? String ?: "ambientSync")
                putExtra(LightmeupService.EXTRA_PRIMARY_COLOR,
                    (pendingEffectArgs["primaryColor"] as? Int) ?: -1)
                putExtra(LightmeupService.EXTRA_SECONDARY_COLOR,
                    (pendingEffectArgs["secondaryColor"] as? Int) ?: -1)
                putExtra(LightmeupService.EXTRA_SPEED,
                    ((pendingEffectArgs["speed"] as? Double) ?: 0.5).toFloat())
                putExtra(LightmeupService.EXTRA_DUTY_CYCLE,
                    ((pendingEffectArgs["dutyCycle"] as? Double) ?: 0.5).toFloat())
                putExtra(LightmeupService.EXTRA_MIRROR_SIDES,
                    (pendingEffectArgs["mirrorSides"] as? Boolean) ?: true)

                @Suppress("UNCHECKED_CAST")
                val cycles = pendingEffectArgs["cycleColors"] as? List<Int>
                if (cycles != null) {
                    putIntegerArrayListExtra(
                        LightmeupService.EXTRA_CYCLE_COLORS,
                        ArrayList(cycles)
                    )
                }
            }
            startForegroundService(si)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                pendingResult?.success(LightmeupService.isRunning)
                pendingResult = null
            }, 500)
        } else {
            Log.e(TAG, "MediaProjection denied")
            pendingResult?.success(false)
            pendingResult = null
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Initialize here, not in configureFlutterEngine, so it's always ready
        // before any launcher callback or method channel call can fire.
        projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    // ── Focus fix ──────────────────────────────────────────────────────────

    override fun onResume() {
        super.onResume()
        window.decorView.post {
            disableFocusHighlight(window.decorView)
            val flutterView = window.decorView.findViewWithTag<android.view.View>("flutter_view")
                ?: window.decorView.findViewById<android.view.View>(android.R.id.content)
            flutterView?.requestFocus()
        }
    }

    private fun disableFocusHighlight(view: android.view.View) {
        view.defaultFocusHighlightEnabled = false
        view.clearFocus()
        if (view is android.view.ViewGroup) {
            for (i in 0 until view.childCount) {
                disableFocusHighlight(view.getChildAt(i))
            }
        }
    }

    // ── Flutter Engine ─────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pendingResult = null

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startService" -> {
                        if (LightmeupService.isRunning) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (pendingResult != null) pendingResult = null

                        pendingBrightness = (call.argument<Double>("brightness") ?: 0.6).toFloat()
                        pendingFrameSkip  = call.argument<Int>("frameSkip") ?: 1
                        pendingSmoothing  = (call.argument<Double>("smoothing") ?: 0.35).toFloat()
                        pendingZoneWidth  = (call.argument<Double>("zoneWidth") ?: 0.15).toFloat()
                        pendingResult     = result

                        // Capture any effect args bundled with startService
                        pendingEffectArgs = call.arguments<Map<String, Any?>>() ?: emptyMap()

                        if (!Settings.System.canWrite(this)) {
                            writeSettingsLauncher.launch(
                                Intent(
                                    Settings.ACTION_MANAGE_WRITE_SETTINGS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        } else {
                            requestProjectionPermission()
                        }
                    }

                    "stopService" -> {
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

                    "updateEffect" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments<Map<String, Any?>>() ?: emptyMap()
                        Log.d(TAG, "updateEffect: mode=${args["mode"]}")
                        LightmeupService.instance?.updateEffect(args)
                            ?: Log.d(TAG, "updateEffect: service not running")
                        result.success(null)
                    }

                    "isRunning" -> result.success(LightmeupService.isRunning)

                    "requestAddTile" -> {
                        LightmeupQSTile.requestTileAdd(this)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    Log.i(TAG, "EventChannel: listening")
                    LightmeupService.colorSink = sink
                }
                override fun onCancel(arguments: Any?) {
                    Log.i(TAG, "EventChannel: cancelled")
                    LightmeupService.colorSink = null
                }
            })
    }

    private fun requestProjectionPermission() {
        projectionLauncher.launch(projectionManager.createScreenCaptureIntent())
    }
}