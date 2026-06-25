package com.example.lightmeup

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.KeyEvent
import android.view.MotionEvent
import android.util.Log

/**
 * KeyInterceptorService — AccessibilityService that intercepts hardware-key
 * events globally and forwards them as panel-open triggers to OverlayService.
 *
 * ── IMPORTANT: Retroid Pocket 6 back buttons ────────────────────────────────
 * The RP6's shoulder / back buttons report as SOURCE_GAMEPAD (not
 * SOURCE_KEYBOARD), so they do NOT arrive via onKeyEvent().  They are
 * delivered via onMotionEvent() as joystick axis or generic motion events.
 *
 * To support them we also override onMotionEvent() and track button presses
 * from the AXIS_* and BUTTON_* constants.  If the user has assigned a
 * "keyboard" key (volume buttons, media keys) we catch those in onKeyEvent().
 * If they assigned a gamepad button we catch it in onMotionEvent() / via
 * a KeyEvent whose source is SOURCE_GAMEPAD.
 *
 * The cleanest approach: intercept ALL KeyEvent sources (not just keyboard).
 * On Android, gamepad buttons also arrive as KeyEvents in some ROM builds
 * (the source just differs).  We log the source so the developer can verify.
 * ────────────────────────────────────────────────────────────────────────────
 *
 * SharedPreferences key names must match those used by SettingsService.dart.
 */
class KeyInterceptorService : AccessibilityService() {

    companion object {
        private const val TAG = "KeyInterceptorService"

        private const val PREFS_NAME      = "FlutterSharedPreferences"  // was "lightmeup_settings"
private const val PREF_LEFT_KEYS  = "flutter.quickPanelLeftKeys"  // flutter. prefix
private const val PREF_RIGHT_KEYS = "flutter.quickPanelRightKeys"
    }

    /** Keys currently held down. */
    private val _heldKeys = mutableSetOf<Int>()

    // ── AccessibilityService callbacks ─────────────────────────────────────

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        val source  = event.source

        // Log every key so we can see what source the RP6 back buttons use.
        Log.v(TAG, "onKeyEvent: action=${event.action} keyCode=$keyCode " +
                   "source=0x${source.toString(16)} repeat=${event.repeatCount}")

        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                _heldKeys.add(keyCode)
                if (event.repeatCount == 0) checkCombos()
            }
            KeyEvent.ACTION_UP -> {
                _heldKeys.remove(keyCode)
            }
        }

        // Never consume — let normal dispatch continue.
        return false
    }

    override fun onAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent) {}
    override fun onInterrupt() {}

    // ── Combo evaluation ───────────────────────────────────────────────────

   private fun checkCombos() {
    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
    val leftCombo  = parseCombo(prefs.getString("flutter.quickPanelLeftKeys",  null))
    val rightCombo = parseCombo(prefs.getString("flutter.quickPanelRightKeys", null))

    Log.d(TAG, "checkCombos: held=$_heldKeys left=$leftCombo right=$rightCombo")

    if (leftCombo != null && _heldKeys == leftCombo) {
        Log.i(TAG, "Left-panel combo matched")
        sendTrigger(OverlayService.ACTION_OPEN_LEFT_PANEL)
        return
    }
    if (rightCombo != null && _heldKeys == rightCombo) {
        Log.i(TAG, "Right-panel combo matched")
        sendTrigger(OverlayService.ACTION_OPEN_RIGHT_PANEL)
    }
}

   private fun parseCombo(raw: String?): Set<Int>? {
    if (raw.isNullOrBlank()) return null
    return raw.split(",")
        .mapNotNull { token ->
            val flutterKeyId = token.trim().toLongOrNull() ?: return@mapNotNull null
            // Try direct mapping first, then fall back to treating it as
            // an Android keycode directly (for any keys not in the map).
            flutterKeyIdToAndroidKeyCode[flutterKeyId]
                ?: token.trim().toIntOrNull()
        }
        .toSet()
        .ifEmpty { null }
}

    // ── Trigger dispatch ───────────────────────────────────────────────────

    private fun sendTrigger(action: String) {
        if (OverlayService.isRunning) {
            val inst = OverlayService.instance
            if (inst == null) {
                Log.e(TAG, "sendTrigger: isRunning=true but instance is null! Starting service.")
                startOverlayWithAction(action)
                return
            }
            val method = when (action) {
                OverlayService.ACTION_OPEN_LEFT_PANEL  -> "openLeftPanel"
                OverlayService.ACTION_OPEN_RIGHT_PANEL -> "openRightPanel"
                else -> return
            }
            Log.i(TAG, "sendTrigger fast-path: $method")
            inst.triggerPanel(method)
        } else {
            startOverlayWithAction(action)
        }
    }

    private val flutterKeyIdToAndroidKeyCode = mapOf(
    // ── RP6 physical back buttons ─────────────────────────────────────────
    0x200000313L to 98,   // Left back button
    0x20000031FL to 101,   // Right back button

    // ── Standard gamepad buttons ──────────────────────────────────────────
    4295032854L to KeyEvent.KEYCODE_BUTTON_A,
    4295032855L to KeyEvent.KEYCODE_BUTTON_B,
    4295032856L to KeyEvent.KEYCODE_BUTTON_X,
    4295032857L to KeyEvent.KEYCODE_BUTTON_Y,
    4295032858L to KeyEvent.KEYCODE_BUTTON_L1,
    4295032859L to KeyEvent.KEYCODE_BUTTON_R1,
    4295032860L to KeyEvent.KEYCODE_BUTTON_L2,
    4295032861L to KeyEvent.KEYCODE_BUTTON_R2,
    4295032862L to KeyEvent.KEYCODE_BUTTON_THUMBL,
    4295032863L to KeyEvent.KEYCODE_BUTTON_THUMBR,
    4295032875L to KeyEvent.KEYCODE_BUTTON_START,
    4295032876L to KeyEvent.KEYCODE_BUTTON_SELECT,
    // D-pad
    4294968068L to KeyEvent.KEYCODE_DPAD_UP,
    4294968069L to KeyEvent.KEYCODE_DPAD_DOWN,
    4294968066L to KeyEvent.KEYCODE_DPAD_LEFT,
    4294968067L to KeyEvent.KEYCODE_DPAD_RIGHT,
    // Volume
    4294969144L to KeyEvent.KEYCODE_VOLUME_UP,
    4294969145L to KeyEvent.KEYCODE_VOLUME_DOWN,
    // Back / menu
    4294968064L to KeyEvent.KEYCODE_BACK,
    4294969149L to KeyEvent.KEYCODE_MENU,
)

    private fun startOverlayWithAction(action: String) {
        val intent = Intent(this, OverlayService::class.java).apply {
            this.action = action
        }
        startForegroundService(intent)
        Log.i(TAG, "OverlayService started with action=$action")
    }
}