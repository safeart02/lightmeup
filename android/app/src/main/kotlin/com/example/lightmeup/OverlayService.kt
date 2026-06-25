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
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel

class OverlayService : Service() {

    companion object {
        private const val TAG        = "OverlayService"
        private const val NOTIF_ID   = 1002
        private const val CHANNEL_ID = "lightmeup_overlay"

        const val ENGINE_ID = "overlay_engine"

        const val ACTION_OPEN_LEFT_PANEL  = "com.example.lightmeup.OPEN_LEFT_PANEL"
        const val ACTION_OPEN_RIGHT_PANEL = "com.example.lightmeup.OPEN_RIGHT_PANEL"

        private const val BUTTON_W_DP = 52
        private const val BUTTON_H_DP = 72

        @Volatile var isRunning = false
            private set

        @Volatile var instance: OverlayService? = null
            private set
    }

    private lateinit var windowManager: WindowManager
    private var flutterEngine: FlutterEngine? = null

    // The panel window starts NOT added to WindowManager. It is added on first
    // open and removed (or made invisible) when closed.  This avoids the
    // ghost-rendering and always-on-top-blocking issues.
    private var panelView:   FlutterView?                = null
    private var panelParams: WindowManager.LayoutParams? = null
    private var panelAttached = true

    private var buttonView:   android.view.View?          = null
    private var buttonParams: WindowManager.LayoutParams? = null

    private var overlayChannel: MethodChannel? = null

    private var buttonX = 0
    private var buttonY = 0

    private var pendingTrigger: String? = null

    override fun onCreate() {
        super.onCreate()
        instance      = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        Log.i(TAG, "onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand action=${intent?.action}")

        val action = intent?.action
        when (action) {
            ACTION_OPEN_LEFT_PANEL, ACTION_OPEN_RIGHT_PANEL -> {
                val method = if (action == ACTION_OPEN_LEFT_PANEL) "openLeftPanel"
                             else "openRightPanel"
                if (overlayChannel != null) {
                    triggerPanel(method)
                } else {
                    Log.i(TAG, "Engine not ready, queuing trigger: $method")
                    pendingTrigger = method
                }
                if (!isRunning) {
                    startForeground(NOTIF_ID, buildNotification())
                    attachWindows()
                    isRunning = true
                }
                return START_STICKY
            }
        }

        startForeground(NOTIF_ID, buildNotification())
        if (panelView == null) attachWindows()
        isRunning = true
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        detachWindows()
        isRunning      = false
        instance       = null
        pendingTrigger = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Panel trigger ──────────────────────────────────────────────────────

    fun triggerPanel(method: String) {
        val channel = overlayChannel ?: run {
            Log.w(TAG, "triggerPanel($method): channel not ready — queuing")
            pendingTrigger = method
            return
        }
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            Log.i(TAG, "triggerPanel invoking: $method")
            channel.invokeMethod(method, null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.d(TAG, "triggerPanel $method: success")
                }
                override fun error(code: String, msg: String?, details: Any?) {
                    Log.e(TAG, "triggerPanel $method error: $code $msg")
                }
                override fun notImplemented() {
                    Log.w(TAG, "triggerPanel $method: notImplemented")
                }
            })
        }
    }

    // ── Window management ──────────────────────────────────────────────────

    private fun attachWindows() {
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

            val channel = MethodChannel(
                eng.dartExecutor.binaryMessenger,
                "com.example.lightmeup/overlay_trigger"
            )
            overlayChannel = channel
            Log.i(TAG, "Overlay MethodChannel created")

            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Flutter tells us a panel opened → attach/show panel window,
                    // make it focusable so it receives touches, hide button.
                   "setFocusable" -> {
    Log.i(TAG, "setFocusable called")
    val view   = panelView   ?: return@setMethodCallHandler result.success(null)
    val params = panelParams ?: return@setMethodCallHandler result.success(null)
    params.alpha = 1f
    params.flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
            WindowManager.LayoutParams.FLAG_LOCAL_FOCUS_MODE
    runCatching { windowManager.updateViewLayout(view, params) }
    // Explicitly request focus for the Flutter view
    view.requestFocus()
    showButtonWindow(false)
    result.success(null)
}

"clearFocusable" -> {
    val view   = panelView   ?: return@setMethodCallHandler result.success(null)
    val params = panelParams ?: return@setMethodCallHandler result.success(null)
    
    // Make invisible and non-interactive again (but keep in WM for vsync)
    params.alpha = 0f
    params.flags = params.flags or
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
    runCatching { windowManager.updateViewLayout(view, params) }
    showButtonWindow(true)
    result.success(null)
}
                    "updateButtonPosition" -> {
                        val x = call.argument<Int>("x") ?: 0
                        val y = call.argument<Int>("y") ?: 0
                        moveButtonWindow(x, y)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

            pendingTrigger?.let { queued ->
                pendingTrigger = null
                android.os.Handler(android.os.Looper.getMainLooper())
                    .postDelayed({ triggerPanel(queued) }, 1000)
                Log.i(TAG, "Replaying queued trigger after 1000ms: $queued")
            }
        }
        flutterEngine = engine

        // Build the FlutterView but do NOT add it to WindowManager yet.
        // It is only added when a panel opens (setFocusable call from Flutter).
        preparePanelView(engine)
        attachButtonWindow()
    }

    // ── Panel window — created once, added/removed on open/close ─────────
    //
    // KEY ARCHITECTURE DECISION:
    // Instead of keeping the panel window in WindowManager at all times with
    // FLAG_NOT_TOUCHABLE, we ADD it when a panel opens and REMOVE it when the
    // panel closes. This means:
    //   • When closed: zero native windows from the panel → zero interception,
    //     zero ghost rendering, home screen fully interactive.
    //   • When open: full-screen focusable window receives all touches.
    //
    // The Flutter engine keeps running in the background (it is attached to the
    // view even when the view is detached from WindowManager), so open latency
    // is just the addView() call (~1 frame).

   private fun preparePanelView(engine: FlutterEngine) {
    val view = FlutterView(applicationContext, FlutterTextureView(applicationContext))
    view.attachToFlutterEngine(engine)
    panelView = view

  panelParams = WindowManager.LayoutParams(
    resources.displayMetrics.widthPixels,   // explicit px width
    resources.displayMetrics.heightPixels,  // explicit px height
    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
            or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
            or WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
            or WindowManager.LayoutParams.FLAG_LOCAL_FOCUS_MODE,
    PixelFormat.TRANSLUCENT
).also {
    it.gravity = Gravity.TOP or Gravity.START
    it.alpha = 0f
}

    // ADD IT TO WINDOW MANAGER IMMEDIATELY so the engine has a surface
    try {
        windowManager.addView(view, panelParams!!)
        panelAttached = true
        Log.i(TAG, "Panel window pre-attached to WindowManager (invisible)")
    } catch (e: Exception) {
        Log.e(TAG, "preparePanelView addView failed: ${e.message}")
    }
}

private fun detachWindows() {
    overlayChannel = null
    buttonView?.let { v ->
        runCatching { windowManager.removeView(v) }
        buttonView = null
    }

    // Need to remove panel from WM since it's now always attached
    panelView?.let { v ->
        if (panelAttached) {
            runCatching { windowManager.removeView(v) }
            panelAttached = false
        }
        v.detachFromFlutterEngine()
        panelView = null
    }
    flutterEngine?.let { eng ->
        FlutterEngineCache.getInstance().remove(ENGINE_ID)
        eng.destroy()
        flutterEngine = null
    }
    Log.i(TAG, "All overlay windows detached")
}

    // ── Button window ──────────────────────────────────────────────────────

    private fun attachButtonWindow() {
        val density = resources.displayMetrics.density
        val wPx = (BUTTON_W_DP * density).toInt()
        val hPx = (BUTTON_H_DP * density).toInt()

        val screenW = resources.displayMetrics.widthPixels
        val screenH = resources.displayMetrics.heightPixels
        buttonX = screenW - wPx
        buttonY = (screenH - hPx) / 2

        val view = android.view.View(applicationContext).also {
            // Non-zero alpha background forces Android to treat this window as
            // a hit-testable surface (fully transparent windows are skipped on
            // many ROMs including AOSP-based Retroid firmware).
            it.setBackgroundColor(0x01000000)
        }
        buttonView = view

        val params = WindowManager.LayoutParams(
            wPx, hPx,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                    or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).also {
            it.gravity = Gravity.TOP or Gravity.START
            it.x = buttonX
            it.y = buttonY
        }
        buttonParams = params

        view.setOnTouchListener { _, motionEvent ->
            if (motionEvent.action == android.view.MotionEvent.ACTION_DOWN) {
                val hPx2   = resources.displayMetrics.density * BUTTON_H_DP
                val method = if (motionEvent.y < hPx2 / 2) "tapLeftButton" else "tapRightButton"
                triggerPanel(method)
                Log.d(TAG, "Button tapped: $method at y=${motionEvent.y}")
            }
            true
        }

        windowManager.addView(view, params)
        Log.i(TAG, "Button window attached at ($buttonX, $buttonY)")
    }

    private fun showButtonWindow(show: Boolean) {
        val view   = buttonView   ?: return
        val params = buttonParams ?: return
        view.visibility = if (show) android.view.View.VISIBLE else android.view.View.GONE
        runCatching { windowManager.updateViewLayout(view, params) }
            .onFailure { Log.w(TAG, "showButtonWindow failed: ${it.message}") }
    }

    private fun moveButtonWindow(xDp: Int, yDp: Int) {
        val density = resources.displayMetrics.density
        buttonX = (xDp * density).toInt()
        buttonY = (yDp * density).toInt()
        val params = buttonParams ?: return
        params.x = buttonX
        params.y = buttonY
        runCatching { windowManager.updateViewLayout(buttonView ?: return, params) }
            .onFailure { Log.w(TAG, "moveButtonWindow failed: ${it.message}") }
    }

    // ── Focus toggling ─────────────────────────────────────────────────────

    fun setPanelFocusable(focusable: Boolean) {
        val view   = panelView   ?: return
        val params = panelParams ?: return

        if (focusable) {
            params.flags = params.flags and
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv() and
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()  and
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL.inv()
        } else {
            params.flags = params.flags or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE  or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        }

        if (panelAttached) {
            runCatching { windowManager.updateViewLayout(view, params) }
                .onFailure { Log.w(TAG, "setPanelFocusable failed: ${it.message}") }
        }

        Log.d(TAG, "setPanelFocusable=$focusable")
    }

    fun setFocusable(focusable: Boolean) = setPanelFocusable(focusable)


    // ── Notification ───────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID, "LightMeUp Overlay", NotificationManager.IMPORTANCE_MIN
        ).apply { description = "Quick-access panel overlay" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
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