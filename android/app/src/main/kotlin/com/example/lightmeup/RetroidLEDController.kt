package com.example.lightmeup

import android.content.Context
import android.graphics.Color
import android.os.IBinder
import android.os.Parcel
import android.provider.Settings
import android.util.Log

/**
 * Controls Retroid Pocket 6 joystick LEDs.
 *
 * Working path: direct sysfs writes using the format confirmed from RPSettings.apk DEX analysis:
 *   /sys/class/sn3112l/led/brightness  ← "1-{R}:{G}:{B}"
 *   /sys/class/sn3112r/led/brightness  ← "1-{R}:{G}:{B}"
 *   /sys/class/sn3112l/led/enable      ← "1" / "0"  (world-writable)
 *   /sys/class/sn3112r/led/enable      ← "1" / "0"  (world-writable)
 *
 * Settings.Secure keys (persists across reboot, requires WRITE_SECURE_SETTINGS):
 *   joystick_led_light_picker_color     — "#RRGGBB,#RRGGBB" (left,right)
 *   joystick_light_enabled              — "1,1" / "0,0"
 *   joystick_handle_light_picker_color  — "#RRGGBB,#RRGGBB,#RRGGBB,#RRGGBB"
 *   joystick_handle_light_enabled       — "1,1,1,1" / "0,0,0,0"
 *   led_light_brightness_percent        — float 0.0–1.0
 *
 * Grant once via ADB:
 *   adb shell pm grant com.example.lightmeup android.permission.WRITE_SECURE_SETTINGS
 */
class RetroidLEDController(private val context: Context) {

    companion object {
        private const val TAG = "RetroidLED"

        // Binder service (SettingsController) — kept for future use but not reliable
        private const val SERVICE_NAME   = "SettingsController"
        private const val DESCRIPTOR     = "com.ro.settings.IExternalControlManager"
        private const val TRANSACTION_SET = 1
        private const val TRANSACTION_GET = 3

        // Settings.Secure keys
        private const val KEY_COLOR          = "joystick_led_light_picker_color"
        private const val KEY_ENABLED        = "joystick_light_enabled"
        private const val KEY_HANDLE_COLOR   = "joystick_handle_light_picker_color"
        private const val KEY_HANDLE_ENABLED = "joystick_handle_light_enabled"
        private const val KEY_BRIGHTNESS     = "led_light_brightness_percent"

        // Sysfs paths
        private const val SYSFS_LEFT_BRIGHT = "/sys/class/sn3112l/led/brightness"
        private const val SYSFS_RIGHT_BRIGHT = "/sys/class/sn3112r/led/brightness"
        private const val SYSFS_LEFT_EN     = "/sys/class/sn3112l/led/enable"
        private const val SYSFS_RIGHT_EN    = "/sys/class/sn3112r/led/enable"
        private const val SYSFS_LEFT_VLED   = "/sys/class/sn3112l/led/vled_enable"
    }

    @Volatile private var brightnessScale = 1.0f
    @Volatile private var binderCache: IBinder? = null

    // ── Public API ───────────────────────────────────────────────────────────────

    fun setZoneColors(leftArgb: Int, rightArgb: Int) {
        val leftHex  = toRgbHex(leftArgb)
        val rightHex = toRgbHex(rightArgb)

        // Primary path: direct sysfs write using confirmed format "1-R:G:B"
        val sysfsOk = writeSysfs(leftArgb, rightArgb)

        // Secondary path: Settings.Secure (persists across reboot)
        val colorValue = if (leftHex == rightHex) leftHex else "$leftHex,$rightHex"
        trySecureWrite(KEY_COLOR, colorValue)
        trySecureWrite(KEY_HANDLE_COLOR, "$leftHex,$leftHex,$leftHex,$leftHex")

        Log.d(TAG, "setZoneColors left=$leftHex right=$rightHex sysfsOk=$sysfsOk")
    }

    fun setColor(argb: Int) = setZoneColors(argb, argb)

    fun setEnabled(on: Boolean) {
        val flag = if (on) "1" else "0"

        // vled_enable requires elevated permissions — attempt but don't rely on it
        if (on) runShell("echo 1 > $SYSFS_LEFT_VLED")

        // enable nodes are world-writable — this works reliably
        runShell("echo $flag > $SYSFS_LEFT_EN && echo $flag > $SYSFS_RIGHT_EN")

        trySecureWrite(KEY_ENABLED, "$flag,$flag")
        trySecureWrite(KEY_HANDLE_ENABLED, "$flag,$flag,$flag,$flag")

        Log.d(TAG, "setEnabled=$on")
    }

    fun setBrightness(fraction: Float) {
        brightnessScale = fraction.coerceIn(0f, 1f)
        val pct = brightnessScale.toString()
        trySecureWrite(KEY_BRIGHTNESS, pct)
        Log.d(TAG, "setBrightness=$brightnessScale")
    }

    fun restore() {
        setBrightness(1.0f)
        setEnabled(true)
        setZoneColors(Color.WHITE, Color.WHITE)
    }

    fun boostSaturation(argb: Int, factor: Float = 2.5f, brightness: Float = 1.0f): Int {
    val hsv = FloatArray(3)
    Color.colorToHSV(argb, hsv)
    hsv[1] = (hsv[1] * factor).coerceIn(0f, 1f)
    hsv[2] = (hsv[2] * 1.2f * brightness).coerceIn(0f, 1f)
    return Color.HSVToColor(hsv)
}

    // ── Sysfs — confirmed working format from RPSettings.apk DEX ────────────────

    /**
     * Writes color to sysfs using the format confirmed from RPSettings.apk source:
     *   d.d("/sys/class/sn3112l/led/brightness", "1-R:G:B", false)
     * where R/G/B are already brightness-scaled integer values (0–255).
     */
    private fun writeSysfs(leftArgb: Int, rightArgb: Int): Boolean {
        return try {
            val leftVal  = "1-${Color.red(leftArgb)}:${Color.green(leftArgb)}:${Color.blue(leftArgb)}"
            val rightVal = "1-${Color.red(rightArgb)}:${Color.green(rightArgb)}:${Color.blue(rightArgb)}"
            java.io.FileWriter(SYSFS_LEFT_BRIGHT).use  { it.write(leftVal) }
            java.io.FileWriter(SYSFS_RIGHT_BRIGHT).use { it.write(rightVal) }
            Log.d(TAG, "sysfs write OK: left=$leftVal right=$rightVal")
            true
        } catch (e: Exception) {
            Log.w(TAG, "sysfs write failed: ${e.message}")
            false
        }
    }

    // ── Shell helper ─────────────────────────────────────────────────────────────

    private fun runShell(command: String): Boolean {
        return try {
            val process = ProcessBuilder("sh", "-c", command)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().readText().trim()
            val exit   = process.waitFor()
            if (exit != 0) Log.w(TAG, "shell[$exit] '$command' → $output")
            else           Log.d(TAG, "shell OK: $command")
            exit == 0
        } catch (e: Exception) {
            Log.e(TAG, "shell exception '$command': ${e.message}")
            false
        }
    }

    // ── Settings.Secure ──────────────────────────────────────────────────────────

    private fun trySecureWrite(key: String, value: String): Boolean {
        return try {
            val ok = Settings.Secure.putString(context.contentResolver, key, value)
            if (ok) Log.d(TAG, "Secure '$key'='$value' ✓")
            else    Log.w(TAG, "Secure '$key' write failed")
            ok
        } catch (e: Exception) {
            Log.w(TAG, "Secure write exception '$key': ${e.message}")
            false
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────

    private fun toRgbHex(argb: Int): String =
        "#%02X%02X%02X".format(Color.red(argb), Color.green(argb), Color.blue(argb))
}