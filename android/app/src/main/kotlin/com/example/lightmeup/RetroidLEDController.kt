package com.example.lightmeup

import android.content.Context
import android.graphics.Color
import android.provider.Settings
import android.util.Log

/**
 * Controls the Retroid Pocket 6 joystick LEDs.
 *
 * The RP6 uses the SN3112 LED driver. RPSettings.apk (com.ro.settings) manages it
 * via Settings.Secure keys and direct sysfs echo commands.
 *
 * Key findings from APK reverse engineering:
 *
 * Settings.Secure keys (require WRITE_SECURE_SETTINGS):
 *   joystick_led_light_picker_color   — color as "#RRGGBB" (single) or "#RRGGBB,#RRGGBB" (L,R)
 *   joystick_light_enabled            — "1" / "0"  (master LED on/off)
 *   joystick_handle_light_enabled     — "1" / "0"  (handle/grip LED zone)
 *   joystick_handle_light_picker_color — "#RRGGBB"  (handle LED color)
 *   led_light_brightness_percent      — "0"–"100"
 *
 * Sysfs paths (require root or system UID):
 *   /sys/class/sn3112l/led/brightness   (left  — format negotiated at runtime, see writeSysfs)
 *   /sys/class/sn3112r/led/brightness   (right)
 *   /sys/class/sn3112l/led/enable       — "1" / "0"
 *   /sys/class/sn3112r/led/enable       — "1" / "0"
 *   /sys/class/sn3112l/led/vled_enable  — "1" / "0"  (voltage rail for LEDs; must be on)
 *
 * Grant the permission once via ADB:
 *   adb shell pm grant com.example.lightmeup android.permission.WRITE_SECURE_SETTINGS
 */
class RetroidLEDController(private val context: Context) {

    companion object {
        private const val TAG = "RetroidLED"

        // ── Settings.Secure keys (discovered from RPSettings.apk DEX strings) ──────
        private const val KEY_COLOR               = "joystick_led_light_picker_color"
        private const val KEY_LIGHT_ENABLED       = "joystick_light_enabled"
        private const val KEY_HANDLE_ENABLED      = "joystick_handle_light_enabled"
        private const val KEY_HANDLE_COLOR        = "joystick_handle_light_picker_color"
        private const val KEY_BRIGHTNESS          = "led_light_brightness_percent"

        // ── Sysfs paths ─────────────────────────────────────────────────────────────
        private const val SYSFS_LEFT_BRIGHT       = "/sys/class/sn3112l/led/brightness"
        private const val SYSFS_RIGHT_BRIGHT      = "/sys/class/sn3112r/led/brightness"
        private const val SYSFS_LEFT_EN           = "/sys/class/sn3112l/led/enable"
        private const val SYSFS_RIGHT_EN          = "/sys/class/sn3112r/led/enable"
        // The voltage rail must be enabled before brightness writes take effect
        private const val SYSFS_LEFT_VLED         = "/sys/class/sn3112l/led/vled_enable"
    }

    @Volatile private var brightnessScale = 1.0f

    // ── Public API ───────────────────────────────────────────────────────────────

    /**
     * Set independent colors for the left and right joystick LEDs.
     * Brightness scaling is applied before writing.
     */
    fun setZoneColors(leftArgb: Int, rightArgb: Int) {
        val leftScaled  = applyBrightness(leftArgb)
        val rightScaled = applyBrightness(rightArgb)

        // 1. Write to sysfs (works when running as system UID or with root)
        writeSysfs(leftScaled, rightScaled)

        // 2. Write to Settings.Secure so RPSettings persists the value across reboots
        val leftHex  = toRgbHex(leftScaled)
        val rightHex = toRgbHex(rightScaled)
        // RPSettings uses "LEFT,RIGHT" when zones differ, plain hex when they match
        val colorValue = if (leftHex == rightHex) leftHex else "$leftHex,$rightHex"
        trySecureWrite(KEY_COLOR, colorValue)
        // Handle LEDs share the same color in the app's UI
        trySecureWrite(KEY_HANDLE_COLOR, leftHex)

        Log.d(TAG, "setZoneColors left=$leftHex right=$rightHex")
    }

    /** Convenience: set both zones to the same color. */
    fun setColor(argb: Int) = setZoneColors(argb, argb)

    /**
     * Enable or disable the joystick LEDs.
     *
     * The RPSettings app writes both the Settings.Secure key AND the sysfs node;
     * we do the same for maximum compatibility.
     */
    fun setEnabled(on: Boolean) {
        val flag = if (on) "1" else "0"

        // Ensure the voltage rail is on before enabling brightness output
        if (on) {
            runShell("echo 1 > $SYSFS_LEFT_VLED")
        }

        val sysfsOk = runShell(
            "echo $flag > $SYSFS_LEFT_EN && echo $flag > $SYSFS_RIGHT_EN"
        )

        // Mirror to Secure settings regardless of sysfs result
        trySecureWrite(KEY_LIGHT_ENABLED, flag)
        trySecureWrite(KEY_HANDLE_ENABLED, flag)

        if (!sysfsOk) {
            Log.w(TAG, "setEnabled=$on: sysfs write failed (may need root/system UID)")
        }
        Log.d(TAG, "setEnabled=$on sysfsOk=$sysfsOk")
    }

    /**
     * Set brightness as a 0.0–1.0 fraction.
     * Writes the percentage to Settings.Secure; the scale is also cached locally
     * so subsequent [setColor] / [setZoneColors] calls use it.
     */
    fun setBrightness(fraction: Float) {
        brightnessScale = fraction.coerceIn(0f, 1f)
        val pct = (brightnessScale * 100).toInt().toString()
        trySecureWrite(KEY_BRIGHTNESS, pct)
        Log.d(TAG, "setBrightness=${brightnessScale} ($pct%)")
    }

    /**
     * Restore to sensible defaults: full brightness, white, enabled.
     * Mirrors what RPSettings does on its "reset" path.
     */
    fun restore() {
        setBrightness(1.0f)
        setEnabled(true)
        setZoneColors(Color.WHITE, Color.WHITE)
    }

    // ── Sysfs writer — tries every format the SN3112 driver accepts ──────────────

    private fun writeSysfs(leftArgb: Int, rightArgb: Int): Boolean {
        val lR = Color.red(leftArgb);   val lG = Color.green(leftArgb);  val lB = Color.blue(leftArgb)
        val rR = Color.red(rightArgb);  val rG = Color.green(rightArgb); val rB = Color.blue(rightArgb)

        // Format 1: "R G B" space-separated (most common for packed SN3112 node)
        if (runShell("echo '$lR $lG $lB' > $SYSFS_LEFT_BRIGHT && echo '$rR $rG $rB' > $SYSFS_RIGHT_BRIGHT")) {
            Log.d(TAG, "sysfs format='R G B' ✓"); return true
        }

        // Format 2: lowercase hex "rrggbb"
        val lHex = "%02x%02x%02x".format(lR, lG, lB)
        val rHex = "%02x%02x%02x".format(rR, rG, rB)
        if (runShell("echo '$lHex' > $SYSFS_LEFT_BRIGHT && echo '$rHex' > $SYSFS_RIGHT_BRIGHT")) {
            Log.d(TAG, "sysfs format=hex ✓"); return true
        }

        // Format 3: "0xRRGGBB" prefixed hex
        if (runShell("echo '0x${lHex.uppercase()}' > $SYSFS_LEFT_BRIGHT && echo '0x${rHex.uppercase()}' > $SYSFS_RIGHT_BRIGHT")) {
            Log.d(TAG, "sysfs format=0xRRGGBB ✓"); return true
        }

        // Format 4: packed 24-bit decimal
        val lDec = (lR shl 16) or (lG shl 8) or lB
        val rDec = (rR shl 16) or (rG shl 8) or rB
        if (runShell("echo $lDec > $SYSFS_LEFT_BRIGHT && echo $rDec > $SYSFS_RIGHT_BRIGHT")) {
            Log.d(TAG, "sysfs format=packed-decimal ✓"); return true
        }

        Log.e(TAG, "All sysfs formats failed — LEDs may only update via Settings.Secure reboot persistence")
        return false
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

    // ── Settings.Secure writer ───────────────────────────────────────────────────

    private fun trySecureWrite(key: String, value: String): Boolean {
        return try {
            val ok = Settings.Secure.putString(context.contentResolver, key, value)
            if (ok) Log.d(TAG, "Secure '$key'='$value' ✓")
            else    Log.w(TAG, "Secure '$key' write returned false (missing WRITE_SECURE_SETTINGS?)")
            ok
        } catch (e: Exception) {
            Log.w(TAG, "Secure write failed '$key': ${e.message}")
            false
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────

    private fun applyBrightness(argb: Int): Int {
        val r = (Color.red(argb)   * brightnessScale).toInt().coerceIn(0, 255)
        val g = (Color.green(argb) * brightnessScale).toInt().coerceIn(0, 255)
        val b = (Color.blue(argb)  * brightnessScale).toInt().coerceIn(0, 255)
        return Color.argb(255, r, g, b)
    }

    /** Formats an ARGB int as "#RRGGBB" — the exact format RPSettings writes. */
    private fun toRgbHex(argb: Int): String =
        "#%02X%02X%02X".format(Color.red(argb), Color.green(argb), Color.blue(argb))
}