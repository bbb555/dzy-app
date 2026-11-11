package com.example.flux

import android.content.Context
import android.util.Log

/**
 * v1.3.0 本机流量累计（服务器是时长套餐，不统计每用户流量，u/d 恒为 0）。
 *
 * 数据来源：hev-socks5-tunnel 的 TUN 计数器 TProxyGetStats()（[1]=tx_bytes 上行，[3]=rx_bytes 下行）。
 * 该计数器在每次隧道停止时被库内部清零，所以这里把每个隧道的用量「结转」到 SharedPreferences：
 *   base   = 历史累计（所有已结束隧道之和）
 *   sess   = 本次会话（用户一次「连接」内，自动切换线路导致的隧道重建也算同一会话）已结束隧道之和
 *   cur    = 当前隧道最近一次检查点（每 15 秒及停止时写入；进程被杀时下次启动会把它结转进 base）
 * 展示值：累计 = base + 当前隧道实时值；本次 = sess + 当前隧道实时值。
 */
object UsageStore {
    private const val TAG = "Flux"
    private const val PREFS = "dzy_usage"

    private val lock = Any()

    private fun p(ctx: Context) = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 读取当前隧道计数器（未运行 / 库不可用返回 null） */
    fun liveCounters(): LongArray? {
        if (!FluxVpnService.isVpnRunning) return null
        return try {
            val a = hev.htproxy.TProxyService.TProxyGetStats()
            if (a != null && a.size >= 4) longArrayOf(a[1], a[3]) else null
        } catch (t: Throwable) {
            null
        }
    }

    /** 隧道启动时调用：把上次异常退出遗留的检查点结转进累计 */
    fun onTunnelStart(ctx: Context) = synchronized(lock) {
        commitLocked(ctx)
        val sp = p(ctx)
        if (sp.getLong("since", 0L) == 0L) sp.edit().putLong("since", System.currentTimeMillis()).apply()
    }

    /** 周期 / 停止前检查点 */
    fun checkpoint(ctx: Context, up: Long, down: Long) = synchronized(lock) {
        val sp = p(ctx)
        // 计数器只增不减；变小说明库已重置（新隧道），先结转旧值
        if (up < sp.getLong("cur_up", 0L) || down < sp.getLong("cur_down", 0L)) commitLocked(ctx)
        p(ctx).edit().putLong("cur_up", up).putLong("cur_down", down).apply()
    }

    /** 隧道停止：最后一次检查点 + 结转 */
    fun onTunnelStop(ctx: Context, finalCounters: LongArray?) = synchronized(lock) {
        if (finalCounters != null) checkpoint(ctx, finalCounters[0], finalCounters[1])
        commitLocked(ctx)
    }

    private fun commitLocked(ctx: Context) {
        val sp = p(ctx)
        val cu = sp.getLong("cur_up", 0L)
        val cd = sp.getLong("cur_down", 0L)
        if (cu == 0L && cd == 0L) return
        sp.edit()
            .putLong("base_up", sp.getLong("base_up", 0L) + cu)
            .putLong("base_down", sp.getLong("base_down", 0L) + cd)
            .putLong("sess_up", sp.getLong("sess_up", 0L) + cu)
            .putLong("sess_down", sp.getLong("sess_down", 0L) + cd)
            .putLong("cur_up", 0L)
            .putLong("cur_down", 0L)
            .apply()
    }

    /** 用户发起新连接：本次会话归零（自动切换线路不调用） */
    fun beginSession(ctx: Context) = synchronized(lock) {
        p(ctx).edit().putLong("sess_up", 0L).putLong("sess_down", 0L).putLong("sess_at", System.currentTimeMillis()).apply()
    }

    /** 用户手动清零累计 */
    fun resetTotal(ctx: Context) = synchronized(lock) {
        val live = liveCounters()
        val e = p(ctx).edit()
            .putLong("base_up", 0L).putLong("base_down", 0L)
            .putLong("since", System.currentTimeMillis())
        // 当前隧道已用的部分不计入新的累计：用负的 base 抵消（结转时 base + cur 正好等于清零后的用量）
        if (live != null) e.putLong("base_up", -live[0]).putLong("base_down", -live[1])
        else e.putLong("cur_up", 0L).putLong("cur_down", 0L)
        e.apply()
    }

    fun snapshot(ctx: Context): Map<String, Any> = synchronized(lock) {
        val sp = p(ctx)
        val live = liveCounters()
        val lu = live?.get(0) ?: 0L
        val ld = live?.get(1) ?: 0L
        // 未运行时 cur 里可能还有未结转的检查点（进程被杀），一并计入
        val cu = if (live == null) sp.getLong("cur_up", 0L) else 0L
        val cd = if (live == null) sp.getLong("cur_down", 0L) else 0L
        mapOf(
            "totalUp" to (sp.getLong("base_up", 0L) + lu + cu).coerceAtLeast(0L),
            "totalDown" to (sp.getLong("base_down", 0L) + ld + cd).coerceAtLeast(0L),
            "sessionUp" to (sp.getLong("sess_up", 0L) + lu + cu).coerceAtLeast(0L),
            "sessionDown" to (sp.getLong("sess_down", 0L) + ld + cd).coerceAtLeast(0L),
            "since" to sp.getLong("since", 0L),
            "sessionAt" to sp.getLong("sess_at", 0L),
            "running" to (live != null),
        )
    }

    fun log(msg: String) = Log.d(TAG, "[Usage] $msg")
}
