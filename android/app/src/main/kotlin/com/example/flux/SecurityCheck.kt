package com.example.flux

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Debug
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

/**
 * v1.3.0 轻量环境检测：只收集信号交给 Dart 层决定提示文案，**任何情况下都不崩溃、不阻断使用**。
 * 真正的防护是：控制面 TLS 公钥固定 + 代码混淆（R8 / Dart --obfuscate）+ 仓库私有化。
 */
object SecurityCheck {
    fun collect(ctx: Context): Map<String, Any> {
        val out = HashMap<String, Any>()
        out["debuggerAttached"] = safe { Debug.isDebuggerConnected() || Debug.waitingForDebugger() }
        out["debuggable"] = safe { (ctx.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0 }
        out["tracerPid"] = safeInt { tracerPid() }
        out["frida"] = safe { fridaSignals() }
        out["root"] = safe { rootSignals() }
        out["httpProxy"] = (System.getProperty("http.proxyHost") ?: "") +
            (System.getProperty("http.proxyPort")?.let { ":$it" } ?: "")
        out["userCaCount"] = safeInt { userCaCount() }
        out["sdk"] = Build.VERSION.SDK_INT
        return out
    }

    private inline fun safe(f: () -> Boolean): Boolean = try { f() } catch (_: Throwable) { false }
    private inline fun safeInt(f: () -> Int): Int = try { f() } catch (_: Throwable) { -1 }

    private fun tracerPid(): Int {
        val line = File("/proc/self/status").useLines { ls -> ls.firstOrNull { it.startsWith("TracerPid:") } }
        return line?.substringAfter(":")?.trim()?.toIntOrNull() ?: 0
    }

    /** Frida：默认端口 27042/27043 有监听，或进程内存映射中出现 frida-agent / gadget */
    private fun fridaSignals(): Boolean {
        for (port in intArrayOf(27042, 27043)) {
            try {
                Socket().use { s ->
                    s.connect(InetSocketAddress("127.0.0.1", port), 80)
                    return true
                }
            } catch (_: Throwable) {}
        }
        try {
            File("/proc/self/maps").useLines { lines ->
                if (lines.any { it.contains("frida", true) || it.contains("gum-js-loop", true) || it.contains("frida-gadget", true) }) return true
            }
        } catch (_: Throwable) {}
        return false
    }

    /** Root（软信号，仅用于提示）：su 二进制 / Magisk / test-keys */
    private fun rootSignals(): Boolean {
        val paths = arrayOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/system/sbin/su",
            "/vendor/bin/su", "/su/bin/su", "/data/local/xbin/su", "/data/local/bin/su",
            "/data/adb/magisk", "/sbin/.magisk",
        )
        if (paths.any { File(it).exists() }) return true
        return Build.TAGS?.contains("test-keys") == true
    }

    /** 用户自行安装的 CA 证书数量（抓包工具通常需要安装用户 CA） */
    private fun userCaCount(): Int {
        val dir = File("/data/misc/user/0/cacerts-added")
        val n = dir.listFiles()?.size
        if (n != null) return n
        // 目录通常无读权限：退而通过 AndroidCAStore 统计 user: 前缀的条目
        return try {
            val ks = java.security.KeyStore.getInstance("AndroidCAStore")
            ks.load(null)
            var c = 0
            val e = ks.aliases()
            while (e.hasMoreElements()) if (e.nextElement().startsWith("user:")) c++
            c
        } catch (_: Throwable) { -1 }
    }
}
