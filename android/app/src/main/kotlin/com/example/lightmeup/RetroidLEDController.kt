package com.example.lightmeup

import android.content.Context
import android.graphics.Color
import android.provider.Settings
import android.util.Log

class RetroidLEDController(private val context: Context) {

    companion object {
        private const val TAG = "RetroidLED"

        // This key lives in Settings.SECURE, not Settings.System
        private const val KEY_COLOR        = "joystick_led_light_picker_color"
        private const val KEY_LEFT_ENABLE  = "left_joystick_light_enabled"
        private const val KEY_RIGHT_ENABLE = "right_joystick_light_enabled"
        private const val KEY_BRIGHT       = "led_brightness_percentage"

        private const val SYSFS_LEFT        = "/sys/class/sn3112l/led/brightness"
        private const val SYSFS_RIGHT       = "/sys/class/sn3112r/led/brightness"
        private const val SYSFS_LEFT_EN     = "/sys/class/sn3112l/led/enable"
        private const val SYSFS_RIGHT_EN    = "/sys/class/sn3112r/led/enable"
    }

    @Volatile private var brightnessScale = 0.6f

    fun canWrite(): Boolean = Settings.System.canWrite(context)

    // ── Public API ──────────────────────────────────────────────────────────

    fun setZoneColors(leftArgb: Int, rightArgb: Int) {
        val leftScaled  = applyBrightness(leftArgb)
        val rightScaled = applyBrightness(rightArgb)

        if (!writeSysfs(leftScaled, rightScaled)) {
            Log.e(TAG, "All sysfs write attempts failed — LEDs unchanged")
        }

        // Also sync to Secure settings (best-effort, requires WRITE_SECURE_SETTINGS
        // granted via adb: adb shell pm grant com.example.lightmeup android.permission.WRITE_SECURE_SETTINGS)
        val leftHex  = toRgbHex(leftScaled)
        val rightHex = toRgbHex(rightScaled)
        val value    = if (leftHex == rightHex) leftHex else "$leftHex,$rightHex"
        trySecureWrite(KEY_COLOR, value)
    }

    fun setColor(argb: Int) = setZoneColors(argb, argb)

    fun setEnabled(on: Boolean) {
        val flag = if (on) "1" else "0"
        val ok = runShell("echo $flag > $SYSFS_LEFT_EN && echo $flag > $SYSFS_RIGHT_EN")
        if (!ok) {
            // Fallback to Secure settings
            trySecureWrite(KEY_LEFT_ENABLE, flag)
            trySecureWrite(KEY_RIGHT_ENABLE, flag)
        }
        Log.d(TAG, "setEnabled=$on sysfsOk=$ok")
    }

    fun setBrightness(fraction: Float) {
        brightnessScale = fraction.coerceIn(0f, 1f)
        val pct = (brightnessScale * 100).toInt().toString()
        trySecureWrite(KEY_BRIGHT, pct)
        Log.d(TAG, "setBrightness=${brightnessScale} ($pct%)")
    }

    fun restore() {
        setBrightness(0.6f)
        setZoneColors(Color.WHITE, Color.WHITE)
        setEnabled(true)
    }

    // ── Sysfs: try every known format the SN3112 driver accepts ────────────

    private fun writeSysfs(leftArgb: Int, rightArgb: Int): Boolean {
        val lR = Color.red(leftArgb);  val lG = Color.green(leftArgb);  val lB = Color.blue(leftArgb)
        val rR = Color.red(rightArgb); val rG = Color.green(rightArgb); val rB = Color.blue(rightArgb)

        // Format 1: space-separated "R G B" — most common for SN3112 packed node
        if (runShell(
            "echo '$lR $lG $lB' > $SYSFS_LEFT && echo '$rR $rG $rB' > $SYSFS_RIGHT"
        )) {
            Log.d(TAG, "sysfs format='R G B' ✓")
            return true
        }

        // Format 2: lowercase hex "rrggbb"
        val lHex = "%02x%02x%02x".format(lR, lG, lB)
        val rHex = "%02x%02x%02x".format(rR, rG, rB)
        if (runShell(
            "echo '$lHex' > $SYSFS_LEFT && echo '$rHex' > $SYSFS_RIGHT"
        )) {
            Log.d(TAG, "sysfs format='rrggbb' hex ✓")
            return true
        }

        // Format 3: "0xRRGGBB" prefixed hex
        if (runShell(
            "echo '0x${lHex.uppercase()}' > $SYSFS_LEFT && echo '0x${rHex.uppercase()}' > $SYSFS_RIGHT"
        )) {
            Log.d(TAG, "sysfs format='0xRRGGBB' ✓")
            return true
        }

        // Format 4: packed 24-bit decimal (original attempt — kept as last resort)
        val lDec = (lR shl 16) or (lG shl 8) or lB
        val rDec = (rR shl 16) or (rG shl 8) or rB
        if (runShell(
            "echo $lDec > $SYSFS_LEFT && echo $rDec > $SYSFS_RIGHT"
        )) {
            Log.d(TAG, "sysfs format=packed-decimal ✓")
            return true
        }

        Log.e(TAG, "All 4 sysfs formats failed for $SYSFS_LEFT / $SYSFS_RIGHT")
        return false
    }

    // ── Shell exec ──────────────────────────────────────────────────────────

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
            Log.e(TAG, "shell failed '$command': ${e.message}")
            false
        }
    }

    // ── Settings.Secure (requires WRITE_SECURE_SETTINGS) ───────────────────

    private fun trySecureWrite(key: String, value: String): Boolean {
        return try {
            Settings.Secure.putString(context.contentResolver, key, value)
            Log.d(TAG, "Secure write '$key'='$value' ✓")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Secure write failed '$key': ${e.message}")
            false
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private fun applyBrightness(argb: Int): Int {
        val r = (Color.red(argb)   * brightnessScale).toInt().coerceIn(0, 255)
        val g = (Color.green(argb) * brightnessScale).toInt().coerceIn(0, 255)
        val b = (Color.blue(argb)  * brightnessScale).toInt().coerceIn(0, 255)
        return Color.argb(255, r, g, b)
    }

    private fun toRgbHex(argb: Int): String =
        "#%02X%02X%02X".format(Color.red(argb), Color.green(argb), Color.blue(argb))
}