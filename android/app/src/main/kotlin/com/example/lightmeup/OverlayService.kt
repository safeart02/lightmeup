package com.example.lightmeup

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader

class OverlayService : Service() {

    companion object {
        private const val TAG        = "OverlayService"
        private const val NOTIF_ID   = 1002
        private const val CHANNEL_ID = "lightmeup_overlay"

        const val ENGINE_ID = "overlay_engine"

        @Volatile var isRunning = false
            private set

        @Volatile var instance: OverlayService? = null
            private set
    }

    private lateinit var windowManager: WindowManager
    private var flutterEngine: FlutterEngine? = null
    private var flutterView: FlutterView?     = null

    override fun onCreate() {
        super.onCreate()
        instance      = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        Log.i(TAG, "onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand")
        startForeground(NOTIF_ID, buildNotification())

        if (flutterView == null) {
            attachOverlayWindow()
        }

        isRunning = true
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        detachOverlayWindow()
        isRunning = false
        instance  = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun attachOverlayWindow() {
        val flutterLoader = FlutterLoader()
        flutterLoader.startInitialization(applicationContext)
        flutterLoader.ensureInitializationComplete(applicationContext, null)

        val engine = FlutterEngine(applicationContext).also { eng ->
            eng.dartExecutor.executeDartEntrypoint(
    DartExecutor.DartEntrypoint(
        flutterLoader.findAppBundlePath(),
        "package:lightmeup/overlay_main.dart",
        "overlayMain"      
    )
)
            FlutterEngineCache.getInstance().put(ENGINE_ID, eng)
        }
        flutterEngine = engine

        val view = FlutterView(applicationContext, FlutterTextureView(applicationContext))
        view.attachToFlutterEngine(engine)
        flutterView = view

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                    or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                    or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
                    or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START

        windowManager.addView(view, params)
        Log.i(TAG, "Overlay window attached")
    }

    private fun detachOverlayWindow() {
        flutterView?.let { v ->
            runCatching { windowManager.removeView(v) }
                .onFailure { Log.w(TAG, "removeView failed: ${it.message}") }
            v.detachFromFlutterEngine()
            flutterView = null
        }
        flutterEngine?.let { eng ->
            FlutterEngineCache.getInstance().remove(ENGINE_ID)
            eng.destroy()
            flutterEngine = null
        }
        Log.i(TAG, "Overlay window detached")
    }

    fun setFocusable(focusable: Boolean) {
        val view   = flutterView ?: return
        val params = view.layoutParams as? WindowManager.LayoutParams ?: return

        if (focusable) {
            params.flags = params.flags and
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv() and
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL.inv() and
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        } else {
            params.flags = params.flags or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }

        runCatching { windowManager.updateViewLayout(view, params) }
            .onFailure { Log.w(TAG, "updateViewLayout failed: ${it.message}") }

        Log.d(TAG, "setFocusable=$focusable")
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "LightMeUp Overlay",
            NotificationManager.IMPORTANCE_MIN
        ).apply { description = "Quick-access panel overlay" }
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
            .setContentText("Quick panel overlay active")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(openApp)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()
    }
}