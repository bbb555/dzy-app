package com.example.flux

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
 * v1.3.0：下拉快捷设置里的「队长云加速」开关。
 *
 * - 已连接：轻点 = 断开（交给 Flutter 走正常断开流程；Flutter 无响应时原生兜底断开）；
 * - 未连接：轻点 = 打开 App 并自动连接（选线 / 验证 / VPN 授权都需要 App 界面，不在后台偷偷连）。
 * 状态取自 [FluxVpnService.isVpnRunning]，VPN 起停时通过 [TileBridge.refresh] 通知系统刷新。
 */
@RequiresApi(Build.VERSION_CODES.N)
class QsTileService : TileService() {

    override fun onTileAdded() {
        super.onTileAdded()
        render()
    }

    override fun onStartListening() {
        super.onStartListening()
        render()
    }

    private fun render(disconnecting: Boolean = false) {
        val tile = qsTile ?: return
        try {
            val on = FluxVpnService.isVpnRunning && !disconnecting
            tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.label = "队长云加速"
            tile.icon = Icon.createWithResource(this, R.drawable.ic_stat_dzy)
            val sub = when {
                disconnecting -> "正在断开…"
                on -> MainActivity.activeNodeName ?: "已连接"
                else -> "未连接"
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = sub
            }
            tile.contentDescription = "队长云加速，$sub"
            tile.updateTile()
        } catch (t: Throwable) {
            Log.w(TAG, "tile render failed: ${t.message}")
        }
    }

    override fun onClick() {
        super.onClick()
        if (FluxVpnService.isVpnRunning) {
            MainActivity.requestDisconnect(applicationContext)
            render(disconnecting = true)
        } else {
            val open = Runnable { openAppToConnect() }
            if (isLocked) unlockAndRun(open) else open.run()
        }
    }

    private fun openAppToConnect() {
        val intent = MainActivity.connectIntent(this)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                // Android 14+（targetSdk 34）只允许传 PendingIntent
                val pi = PendingIntent.getActivity(
                    this, 7, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                startActivityAndCollapse(pi)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "tile open app failed: ${t.message}")
            try {
                startActivity(intent)
            } catch (_: Throwable) {
            }
        }
    }

    companion object {
        private const val TAG = "Flux"
    }
}

/** 通知系统刷新快捷开关（开关未添加到面板时系统会忽略） */
object TileBridge {
    @JvmStatic
    fun refresh(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                TileService.requestListeningState(ctx, ComponentName(ctx, QsTileService::class.java))
            } catch (_: Throwable) {
            }
        }
    }
}

/** 连接通知上的「断开」按钮 */
class VpnActionReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == ACTION_DISCONNECT) {
            MainActivity.requestDisconnect(context.applicationContext)
        }
    }

    companion object {
        const val ACTION_DISCONNECT = "com.dzy.cloud.action.DISCONNECT"
    }
}
