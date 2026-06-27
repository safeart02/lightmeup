package com.example.lightmeup

import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import java.util.function.Consumer

class LightmeupQSTile : TileService() {

    companion object {
        private const val TAG = "LightmeupTile"
        private const val STOP_COOLDOWN_MS = 1500L

        const val ACTION_REFRESH_TILE = "com.example.lightmeup.REFRESH_TILE"

        fun requestTileAdd(activity: android.app.Activity) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
            val sbm = activity.getSystemService(StatusBarManager::class.java) ?: return
            sbm.requestAddTileService(
                ComponentName(activity, LightmeupQSTile::class.java),
                "LightMeUp",
                Icon.createWithResource(activity, android.R.drawable.ic_menu_compass),
                activity.mainExecutor,
                Consumer { result -> Log.d(TAG, "requestAddTileService result=$result") }
            )
        }
    }

    private val handler = Handler(Looper.getMainLooper())

    // True while we're waiting for the service to finish shutting down.
    // Taps during this window are ignored so the user can't accidentally
    // restart the service while onDestroy is still running.
    private var stopping = false

    // ── BroadcastReceiver ──────────────────────────────────────────────────

    private val refreshReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == ACTION_REFRESH_TILE) {
                Log.d(TAG, "Received REFRESH_TILE broadcast")
                stopping = false
                syncTile()
            }
        }
    }

    // ── TileService callbacks ──────────────────────────────────────────────

    override fun onStartListening() {
        super.onStartListening()
        val filter = android.content.IntentFilter(ACTION_REFRESH_TILE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(refreshReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(refreshReceiver, filter)
        }
        syncTile()
    }

    override fun onStopListening() {
        super.onStopListening()
        handler.removeCallbacksAndMessages(null)
        try { unregisterReceiver(refreshReceiver) } catch (_: Exception) {}
    }

    override fun onClick() {
        super.onClick()
        if (stopping) {
            Log.d(TAG, "onClick ignored — stop cooldown active")
            return
        }
        if (LightmeupService.isRunning) stopLightmeup() else startLightmeup()
    }

    override fun onBind(intent: Intent): IBinder? = super.onBind(intent)

    // ── Actions ────────────────────────────────────────────────────────────

    private fun startLightmeup() {
        Log.d(TAG, "Tile tapped: starting service")
        setTileActive()
        val launch = Intent(this, TilePermissionActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivityAndCollapse(launch)
    }

    private fun stopLightmeup() {
        Log.d(TAG, "Tile tapped: stopping service")
        LightmeupService.isRunning = false
        stopping = true
        setTileInactive()
        stopService(Intent(this, LightmeupService::class.java))
        // Clear the cooldown after a safe window in case onDestroy never fires
        // (e.g. service was already dead), so the tile doesn't get stuck.
        handler.postDelayed({ stopping = false }, STOP_COOLDOWN_MS)
    }

    // ── Tile state helpers ─────────────────────────────────────────────────

    private fun setTileActive() {
        val tile = qsTile ?: return
        tile.state = Tile.STATE_ACTIVE
        tile.label = "LightMeUp"
        tile.contentDescription = "LightMeUp active – tap to stop"
        tile.updateTile()
    }

    private fun setTileInactive() {
        val tile = qsTile ?: return
        tile.state = Tile.STATE_INACTIVE
        tile.label = "LightMeUp"
        tile.contentDescription = "LightMeUp off – tap to start"
        tile.updateTile()
    }

    private fun syncTile() {
        if (LightmeupService.isRunning) setTileActive() else setTileInactive()
    }
}