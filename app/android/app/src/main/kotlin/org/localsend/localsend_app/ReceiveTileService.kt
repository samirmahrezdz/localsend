package org.localsend.localsend_app

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * Shared state between [ReceiveTileService] and [MainActivity].
 *
 * Both run in the main process:
 * - [isActiveInProcess] reflects whether the server and foreground notification are actually
 *   running in this live OS process (reset on reboot / process kill / MainActivity destroy).
 * - `pending` holds a toggle made from the tile that the Dart side has not applied yet
 *   (e.g. because the Flutter engine was not running).
 */
object ReceiveTileState {
    private const val PREFS = "localsend_receive_tile"
    private const val KEY_PENDING = "pending"
    private const val PENDING_NONE = -1

    /** Set by [MainActivity] while its Flutter engine is attached. Tells Dart to apply the pending command. */
    var commandListener: (() -> Unit)? = null

    /** Live in-process listening status set by Dart via [MainActivity]. */
    @Volatile
    var isActiveInProcess = false

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun hasPending(context: Context): Boolean = prefs(context).getInt(KEY_PENDING, PENDING_NONE) != PENDING_NONE

    fun isEnabled(context: Context): Boolean {
        val pending = prefs(context).getInt(KEY_PENDING, PENDING_NONE)
        if (pending != PENDING_NONE) {
            return pending == 1
        }
        return commandListener != null && isActiveInProcess
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        if (hasPending(context)) {
            return
        }
        isActiveInProcess = enabled
        requestRefresh(context)
    }

    fun clearActive(context: Context) {
        isActiveInProcess = false
        requestRefresh(context)
    }

    fun setPending(context: Context, enabled: Boolean) {
        isActiveInProcess = enabled
        prefs(context).edit().putInt(KEY_PENDING, if (enabled) 1 else 0).apply()
    }

    /** Returns and clears the pending command: true = enable, false = disable, null = nothing pending. */
    fun consumePending(context: Context): Boolean? {
        val p = prefs(context)
        val value = p.getInt(KEY_PENDING, PENDING_NONE)
        if (value == PENDING_NONE) {
            return null
        }
        p.edit().putInt(KEY_PENDING, PENDING_NONE).apply()
        return value == 1
    }

    fun requestRefresh(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                TileService.requestListeningState(
                    context.applicationContext,
                    ComponentName(context.applicationContext, ReceiveTileService::class.java)
                )
            } catch (e: Exception) {
                Log.w("ReceiveTileService", "Could not request tile refresh", e)
            }
        }
    }
}

/**
 * Quick settings toggle: "Always receive".
 *
 * When active, LocalSend keeps its server and the foreground notification alive in the background
 * so files can be received at any time. Enabling requires the app in the foreground (Android 12+
 * forbids starting a foreground service from the background), so the tile briefly opens the app,
 * which then moves itself back. Disabling works without opening the app.
 */
@RequiresApi(Build.VERSION_CODES.N)
class ReceiveTileService : TileService() {
    companion object {
        const val EXTRA_FROM_RECEIVE_TILE = "org.localsend.localsend_app.FROM_RECEIVE_TILE"
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTile(ReceiveTileState.isEnabled(this))
    }

    override fun onClick() {
        super.onClick()
        val target = !ReceiveTileState.isEnabled(this)
        ReceiveTileState.setPending(this, target)
        updateTile(target)

        val listener = ReceiveTileState.commandListener
        if (!target) {
            // Stopping a foreground service is always allowed. If the engine is not running,
            // the service is not running either and the pending command is applied on next start.
            listener?.invoke()
            return
        }

        if (listener != null && MainActivity.isInForeground) {
            listener.invoke()
            return
        }

        launchApp()
    }

    private fun updateTile(enabled: Boolean) {
        val tile = qsTile ?: return
        tile.state = if (enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.receive_tile_label)
        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile_receive)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = getString(if (enabled) R.string.receive_tile_on else R.string.receive_tile_off)
        }
        tile.updateTile()
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun launchApp() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(EXTRA_FROM_RECEIVE_TILE, true)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(this, 1, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                )
            } else {
                startActivityAndCollapse(intent)
            }
        } catch (e: Exception) {
            Log.w("ReceiveTileService", "Could not open LocalSend", e)
        }
    }
}
