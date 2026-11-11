package com.example.flux

import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File

/**
 * VPN 服务 - 基于 v2rayNG 的实现
 * 将 VPN 流量转发到本地 SOCKS5 代理 (127.0.0.1:10808)
 */
class FluxVpnService : VpnService() {
    private var mInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    private var tun2SocksService: Tun2SocksControl? = null
    // v1.3.0：本机流量累计检查点（每 15 秒），防止进程被杀时丢失整段用量
    private val usageHandler = Handler(Looper.getMainLooper())
    private val usageTick = object : Runnable {
        override fun run() {
            if (!isRunning) return
            try {
                UsageStore.liveCounters()?.let { UsageStore.checkpoint(applicationContext, it[0], it[1]) }
            } catch (_: Throwable) {}
            usageHandler.postDelayed(this, 15_000L)
        }
    }
    private val connectivity by lazy { getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager }
    private val defaultNetworkRequest by lazy {
        NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            .build()
    }
    private val defaultNetworkCallback by lazy {
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                setUnderlyingNetworks(arrayOf(network))
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities
            ) {
                setUnderlyingNetworks(arrayOf(network))
            }

            override fun onLost(network: Network) {
                setUnderlyingNetworks(null)
            }
        }
    }
    
    companion object {
        private const val TAG = "Flux"
        const val ACTION_START = "com.example.flux.VPN_START"
        const val ACTION_STOP = "com.example.flux.VPN_STOP"
        private const val VPN_ADDRESS = "10.0.0.2"
        private const val VPN_ROUTE = "0.0.0.0"
        private const val VPN_MTU = 1450  // 移动网络下适当提高 MTU，减少分片提升吞吐
        private const val SOCKS_PROXY_HOST = "127.0.0.1"
        private const val SOCKS_PROXY_PORT = 10808
        private const val VPN_ADDRESS_V6 = "fd00:1:fd00:1::2"

        @Volatile
        var isVpnRunning: Boolean = false
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "FluxVpnService onCreate")
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
        Log.d(TAG, "FluxVpnService onDestroy")
    }

    override fun onRevoke() {
        stopVpn()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                Log.d(TAG, "Starting VPN service")
                startVpn()
            }
            ACTION_STOP -> {
                Log.d(TAG, "Stopping VPN service")
                stopVpn()
            }
        }
        return START_STICKY
    }

    /**
     * 启动 VPN 服务
     */
    private fun startVpn() {
        if (isRunning) {
            Log.d(TAG, "VPN already running")
            return
        }

        setupService()
    }

    /**
     * 设置 VPN 服务
     */
    private fun setupService() {
        // 检查 VPN 权限
        val prepare = prepare(this)
        if (prepare != null) {
            Log.e(TAG, "VPN permission not granted")
            return
        }

        // 配置 VPN 接口
        if (!configureVpnService()) {
            Log.e(TAG, "Failed to configure VPN service")
            return
        }

        // 启动 tun2socks
        runTun2socks()
    }

    /**
     * 配置 VPN 服务
     */
    private fun configureVpnService(): Boolean {
        val builder = Builder()

        // 配置网络设置
        configureNetworkSettings(builder)

        // 配置应用规则（禁用 VPN 服务自身，避免流量回环）
        configurePerAppProxy(builder)

        // 关闭旧的接口（如果存在）
        try {
            mInterface?.close()
        } catch (ignored: Exception) {
            // ignored
        }

        // 配置平台特定功能
        configurePlatformFeatures(builder)

        // 创建新的 VPN 接口
        try {
            mInterface = builder.establish()
            isRunning = true
            isVpnRunning = true
            MainActivity.emitVpnStatus(true)
            Log.d(TAG, "VPN interface established successfully")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to establish VPN interface", e)
            stopVpn()
            return false
        }
    }
    
    /**
     * 配置应用规则（禁用 VPN 服务自身，避免流量回环）
     */
    private fun configurePerAppProxy(builder: Builder) {
        val selfPackageName = packageName
        try {
            // 禁用自身应用，避免流量回环
            builder.addDisallowedApplication(selfPackageName)
            Log.d(TAG, "Disallowed self package: $selfPackageName")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to configure per-app proxy: ${e.message}")
        }
    }

    /**
     * 配置网络设置（IP 地址、路由、DNS）
     * 基于 v2rayNG 的实现
     */
    private fun configureNetworkSettings(builder: Builder) {
        // 设置 MTU
        builder.setMtu(VPN_MTU)
        
        // 配置 IPv4 地址（使用 10.0.0.2，与 v2rayNG OPTION_3 类似）
        builder.addAddress(VPN_ADDRESS, 30) // /30 子网

        // 配置路由（路由所有流量）
        // v2rayNG 默认路由所有流量，除非启用 bypass LAN
        builder.addRoute("0.0.0.0", 0)

        // 配置 IPv6（移动网络下更常用） - 暂时禁用以解决连接问题
        // builder.addAddress(VPN_ADDRESS_V6, 126)
        // builder.addRoute("::", 0)

        // 配置 DNS 服务器
        // 移动网络下优先使用国内公共 DNS，降低解析延迟
        builder.addDnsServer("223.5.5.5")  // AliDNS
        builder.addDnsServer("119.29.29.29")  // DNSPod
        builder.addDnsServer("1.1.1.1")  // Cloudflare DNS（备选）

        // 设置会话名称
        builder.setSession("队长云加速")
    }

    /**
     * 配置平台特定功能
     */
    private fun configurePlatformFeatures(builder: Builder) {
        // Android P (API 28) 及以上：绑定默认网络，避免 VPN 出站回环
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                connectivity.requestNetwork(defaultNetworkRequest, defaultNetworkCallback)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to request default network", e)
            }
        }

        // Android Q (API 29) 及以上：设置非计量网络
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }
    }

    /**
     * 启动 tun2socks
     * 基于 v2rayNG 的实现方式
     */
    private fun runTun2socks() {
        val vpnInterface = mInterface ?: run {
            Log.e(TAG, "VPN interface not available")
            return
        }

        // 使用 TProxyService（基于 v2rayNG 的实现）
        tun2SocksService = TProxyService(
            context = applicationContext,
            vpnInterface = vpnInterface,
            isRunningProvider = { isRunning },
            restartCallback = { runTun2socks() }
        )

        try { UsageStore.onTunnelStart(applicationContext) } catch (_: Throwable) {}
        tun2SocksService?.startTun2Socks()
        usageHandler.removeCallbacks(usageTick)
        usageHandler.postDelayed(usageTick, 15_000L)
    }

    /**
     * 停止 VPN 服务
     */
    private fun stopVpn() {
        if (!isRunning) return

        try {
            // v1.3.0：停止前读取最后一次计数并结转（库在停止时会清零计数器）
            usageHandler.removeCallbacks(usageTick)
            try { UsageStore.onTunnelStop(applicationContext, UsageStore.liveCounters()) } catch (_: Throwable) {}
            isRunning = false
            isVpnRunning = false
            MainActivity.emitVpnStatus(false)
            // Core is managed by MainActivity now
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    connectivity.unregisterNetworkCallback(defaultNetworkCallback)
                } catch (ignored: Exception) {
                    // ignored
                }
            }
            setUnderlyingNetworks(null)

            // 停止 tun2socks
            tun2SocksService?.stopTun2Socks()
            tun2SocksService = null

            // 关闭 VPN 接口
            mInterface?.close()
            mInterface = null

            // 停止服务
            stopSelf()

            Log.d(TAG, "VPN stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping VPN", e)
        }
    }
}

/**
 * Tun2Socks 控制接口
 * 基于 v2rayNG 的 Tun2SocksControl 接口
 */
interface Tun2SocksControl {
    /**
     * 启动 tun2socks 进程
     */
    fun startTun2Socks()

    /**
     * 停止 tun2socks 进程
     */
    fun stopTun2Socks()
}

/**
 * TProxyService - 管理 tun2socks 进程
 * 基于 v2rayNG 的 TProxyService 实现
 * 
 * 注意：完整实现需要 hev-socks5-tunnel native 库
 * 可以从 v2rayNG 项目复制相关代码和库文件
 */
class TProxyService(
    private val context: Context,
    private val vpnInterface: ParcelFileDescriptor,
    private val isRunningProvider: () -> Boolean,
    private val restartCallback: () -> Unit
) : Tun2SocksControl {
    
    companion object {
        private const val TAG = "Flux"
        private const val SOCKS_PROXY_HOST = "127.0.0.1"
        private const val SOCKS_PROXY_PORT = 10808
        private const val TUN_MTU = 1450
        private const val TUN_IPV4 = "10.0.0.2"
        private const val TUN_IPV6 = "fd00:1:fd00:1::2"
        
        // hev-socks5-tunnel native 库的 JNI 接口
        // 注意：需要将 hev-socks5-tunnel 库添加到项目中才能使用
        // 可以从 v2rayNG 项目复制相关库文件，或从 https://github.com/heiher/hev-socks5-tunnel 编译
        // 注意：实际的 native 方法在 hev.htproxy.TProxyService 中声明
        // 库会在 hev.htproxy.TProxyService 初始化时自动加载
    }

    override fun startTun2Socks() {
        // 构建配置文件内容
        val configContent = buildConfig()
        val configFile = File(context.filesDir, "hev-socks5-tunnel.yaml").apply {
            writeText(configContent)
        }
        
        Log.d(TAG, "Tun2Socks config file: ${configFile.absolutePath}")
        Log.d(TAG, "Config content:\n$configContent")

        try {
            // 调用 hev.htproxy.TProxyService 的 native 方法
            hev.htproxy.TProxyService.TProxyStartService(configFile.absolutePath, vpnInterface.fd)
            Log.d(TAG, "Tun2Socks started successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "hev-socks5-tunnel library not found. Please add the native library to your project.", e)
            Log.e(TAG, "You can copy the library from v2rayNG project or compile it from: https://github.com/heiher/hev-socks5-tunnel")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start Tun2Socks: ${e.message}", e)
            throw e
        }
    }

    private fun buildConfig(): String {
        return buildString {
            appendLine("tunnel:")
            appendLine("  mtu: $TUN_MTU")  // 与 VPN MTU 保持一致，避免数据包过大
            appendLine("  ipv4: $TUN_IPV4")
            appendLine("  ipv6: '$TUN_IPV6'")
            appendLine()
            appendLine("socks5:")
            appendLine("  port: $SOCKS_PROXY_PORT")
            appendLine("  address: $SOCKS_PROXY_HOST")
            appendLine("  udp: 'udp'")
            appendLine()
            appendLine("misc:")
            appendLine("  tcp-read-write-timeout: 300000")
            appendLine("  udp-read-write-timeout: 60000")
            appendLine("  log-level: warn")
        }
    }

    override fun stopTun2Socks() {
        try {
            // 调用 hev.htproxy.TProxyService 的 native 方法
            hev.htproxy.TProxyService.TProxyStopService()
            Log.d(TAG, "Tun2Socks stopped successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "hev-socks5-tunnel library not found, skip stop", e)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop Tun2Socks: ${e.message}", e)
        }
    }
}
