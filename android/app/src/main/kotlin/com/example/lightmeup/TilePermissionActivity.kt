package com.example.lightmeup

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.ComponentActivity

/**
 * Transparent, Flutter-free activity whose only job is to run the
 * WRITE_SETTINGS → MediaProjection permission flow on behalf of the
 * Quick Settings tile, then immediately finish.
 *
 * Uses ComponentActivity (always available via flutter's existing
 * androidx.activity dependency) instead of AppCompatActivity so no
 * extra gradle dependency is needed.
 *
 * The transparent theme (declared in AndroidManifest) means the screen
 * behind stays fully visible the whole time — no gray flash.
 */
class TilePermissionActivity : ComponentActivity() {

    companion object {
        private const val TAG = "TilePermissionActivity"
    }

    private lateinit var projectionManager: MediaProjectionManager

    // Guard against re-entrancy: only kick off the flow once per instance.
    private var flowStarted = false

    // ── Activity Result Launchers ──────────────────────────────────────────

    private val writeSettingsLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { _: ActivityResult ->
        if (Settings.System.canWrite(this)) {
            Log.i(TAG, "WRITE_SETTINGS granted → requesting projection")
            requestProjection()
        } else {
            Log.w(TAG, "WRITE_SETTINGS denied — aborting")
            finish()
        }
    }

    private val projectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result: ActivityResult ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            Log.i(TAG, "MediaProjection granted → starting service")
            startLightmeupService(result.resultCode, result.data!!)
        } else {
            Log.w(TAG, "MediaProjection denied — aborting")
            // The tile was flipped to active optimistically; correct it back.
            sendBroadcast(android.content.Intent(LightmeupQSTile.ACTION_REFRESH_TILE).apply {
                setPackage(packageName)
            })
        }
        // Always finish, success or not.
        finish()
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // savedInstanceState != null means we were recreated (e.g. rotation).
        // The launchers will deliver their pending results automatically;
        // don't re-launch the flow or we'd stack duplicate dialogs.
        if (savedInstanceState == null) {
            startFlow()
        }
    }

    // ── Flow ───────────────────────────────────────────────────────────────

    private fun startFlow() {
        if (flowStarted) return
        flowStarted = true

        if (LightmeupService.isRunning) {
            Log.i(TAG, "Service already running — nothing to do")
            finish()
            return
        }

        if (!Settings.System.canWrite(this)) {
            Log.i(TAG, "Need WRITE_SETTINGS — launching settings screen")
            writeSettingsLauncher.launch(
                Intent(
                    Settings.ACTION_MANAGE_WRITE_SETTINGS,
                    Uri.parse("package:$packageName")
                )
            )
        } else {
            requestProjection()
        }
    }

    private fun requestProjection() {
        Log.i(TAG, "Launching MediaProjection consent dialog")
        projectionLauncher.launch(projectionManager.createScreenCaptureIntent())
    }

    // ── Service start ──────────────────────────────────────────────────────

    private fun startLightmeupService(resultCode: Int, data: Intent) {
        // Read the last-saved settings so the tile always uses the user's
        // chosen brightness / smoothing / effect — not hardcoded defaults.
        // flutter_secure_storage uses EncryptedSharedPreferences under the hood;
        // the underlying file name on Android is "FlutterSecureStorage".
        val prefs = getSharedPreferences("FlutterSecureStorage", MODE_PRIVATE)

        val brightness = prefs.getString("brightness", "0.6")?.toFloatOrNull() ?: 0.6f
        val frameSkip  = prefs.getString("frameSkip",  "1")?.toIntOrNull()     ?: 1
        val smoothing  = prefs.getString("smoothing",  "0.35")?.toFloatOrNull() ?: 0.35f
        val zoneWidth  = prefs.getString("zoneWidth",  "0.15")?.toFloatOrNull() ?: 0.15f
        val effectMode = prefs.getString("ledEffect",  "ambientSync") ?: "ambientSync"

        Log.i(TAG, "Starting service: brightness=$brightness frameSkip=$frameSkip " +
                   "smoothing=$smoothing zoneWidth=$zoneWidth effect=$effectMode")

        val si = Intent(this, LightmeupService::class.java).apply {
            putExtra(LightmeupService.EXTRA_RESULT_CODE, resultCode)
            putExtra(LightmeupService.EXTRA_DATA,        data)
            putExtra(LightmeupService.EXTRA_BRIGHTNESS,  brightness)
            putExtra(LightmeupService.EXTRA_FRAME_SKIP,  frameSkip)
            putExtra(LightmeupService.EXTRA_SMOOTHING,   smoothing)
            putExtra(LightmeupService.EXTRA_ZONE_WIDTH,  zoneWidth)
            putExtra(LightmeupService.EXTRA_EFFECT_MODE, effectMode)
        }
        startForegroundService(si)

        // Small delay so onStartCommand has time to set isRunning = true before
        // the tile reads it. 300 ms is enough even on slow devices.
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            sendBroadcast(android.content.Intent(LightmeupQSTile.ACTION_REFRESH_TILE).apply {
                setPackage(packageName)
            })
        }, 300)
    }
}