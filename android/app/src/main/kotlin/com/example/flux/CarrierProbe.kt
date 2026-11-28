package com.example.flux

import android.content.Context
import android.os.Build
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager

/**
 * v1.6.3：读取「当前接入运营商」，供 Dart 侧按运营商选线使用。
 *
 * 判定优先级（与 DESIGN.md 一致）：
 *  1. `getNetworkOperator()` —— 当前注册的网络（移动数据在手时最准）；
 *  2. 为空（Wi-Fi、飞行模式、刚开机没驻网）→ `getSimOperator()` 兜底（SIM 卡归属）；
 *  3. 双卡 → 取「默认数据卡」（SubscriptionManager.getDefaultDataSubscriptionId）；
 *  4. 仍拿不到（无 SIM / 无权限 / 境外 MCC）→ 返回 null，由 Dart 侧走服务端 whoami 兜底。
 *
 * 只认中国大陆 MCC 460；460 段里没登记在册的 MNC（虚拟运营商/物联网卡等）归「其他」。
 * 不做任何缓存：调用频率由 Dart 侧缓存（30 分钟）控制。
 */
object CarrierProbe {

    /** MCC+MNC（6 位）→ 归一化运营商名 */
    private val MCC_MNC: Map<String, String> = mapOf(
        "46000" to "移动", "46002" to "移动", "46004" to "移动",
        "46007" to "移动", "46008" to "移动",
        "46001" to "联通", "46006" to "联通", "46009" to "联通",
        "46003" to "电信", "46005" to "电信", "46011" to "电信",
        "46020" to "移动", // 中国铁通（已并入移动）
        "46015" to "其他"  // 中国广电
    )

    /**
     * @return `{"carrier": "电信|联通|移动|其他", "operator": "46003", "source": "network|sim"}`
     *         或 null（拿不到/无权限/非大陆网络）。
     */
    fun read(ctx: Context): Map<String, Any?>? {
        val tm = telephonyForDefaultData(ctx) ?: return null
        val netOp = safe { tm.networkOperator }?.trim().orEmpty()
        val simOp = safe { tm.simOperator }?.trim().orEmpty()
        val operator = when {
            netOp.isNotEmpty() -> netOp
            simOp.isNotEmpty() -> simOp
            else -> return null
        }
        val carrier = carrierOf(operator) ?: return null
        return mapOf(
            "carrier" to carrier,
            "operator" to operator,
            "source" to if (netOp.isNotEmpty()) "network" else "sim"
        )
    }

    /** 运营商编码 → 名；非 460 段返回 null（境外/无 SIM） */
    fun carrierOf(operator: String): String? {
        val op = operator.trim()
        if (op.length < 4 || !op.startsWith("460")) return null
        return MCC_MNC[op] ?: "其他"
    }

    /** 双卡取默认数据卡；老系统或异常时回退到默认 TelephonyManager */
    private fun telephonyForDefaultData(ctx: Context): TelephonyManager? {
        val base = ctx.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return base
        return try {
            val subId = SubscriptionManager.getDefaultDataSubscriptionId()
            if (subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                base.createForSubscriptionId(subId)
            } else {
                base
            }
        } catch (t: Throwable) {
            base // 无 READ_PHONE_STATE 时部分 ROM 会抛 SecurityException
        }
    }

    private inline fun <T> safe(block: () -> T): T? =
        try {
            block()
        } catch (t: Throwable) {
            null // SecurityException：无权限时按「拿不到」处理，不 crash
        }
}
