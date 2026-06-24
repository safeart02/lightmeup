package com.example.lightmeup

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.KeyEvent
import android.util.Log

class KeyInterceptorService : AccessibilityService() {

    companion object {
        private const val TAG = "KeyInterceptorService"
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        val action = event.action

        // Example: Detect if Volume Down is pressed
        // (Adapt this logic to match whatever custom combination you are tracking)
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN && action == KeyEvent.ACTION_DOWN) {
            Log.i(TAG, "Volume Down detected globally!")

            // Trigger your OverlayService to open or flip focusable mode
            if (!OverlayService.isRunning) {
                val intent = Intent(this, OverlayService::class.java)
                startForegroundService(intent)
            } else {
                // If it's already running, you can send an intent or use a state toggle
                OverlayService.instance?.setFocusable(true)
            }
            
            // Return true if you want to consume the click (prevent system volume slider)
            // Return false if you want the button to behave normally too
            return false 
        }

        return super.onKeyEvent(event)
    }

    override fun onAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent) {}
    override fun onInterrupt() {}
}