package com.example.flux

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.TrafficStats
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Process as AndroidProcess
import android.provider.Settings
import androidx.core.content.FileProvider
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.BufferedReader
import java.io.InputStreamReader
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.flux/v2ray"
    private val STATUS_CHANNEL = "com.example.flux/v2ray_status"
    private var isV2rayRunning = false
    private var xrayProcess: Process? = null
    // private var hysteria2Process: Process? = null // Removed
    private var currentProtocol: String = ""
    private var isInitialized = false
    private var isGeoDataReady = false
    // v1.3.0：VPN 授权弹窗状态
    @Volatile private var vpnPermissionPending = false
    @Volatile private var vpnPermissionDenied = false
    
    companion object {
        private const val TAG = "Flux"
        private const val REQUEST_VPN_PERMISSION = 1
        @Volatile
        private var vpnStatusSink: EventChannel.EventSink? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        @JvmStatic
        fun emitVpnStatus(isConnected: Boolean) {
            mainHandler.post {
                vpnStatusSink?.success(isConnected)
            }
        }

        // ───── v1.3.0：快捷开关 / 通知「断开」/ 网络切换 → Flutter ─────
        private const val EXTRA_ACTION = "dzy_action"
        private const val REQUEST_NOTIFICATION_PERMISSION = 2

        @Volatile
        private var methodChannel: MethodChannel? = null

        @Volatile
        private var activityRef: java.lang.ref.WeakReference<MainActivity>? = null

        /** 冷启动时 Flutter 还没准备好：先记下，Flutter 初始化完成后通过 takeSystemAction 取走 */
        @Volatile
        private var pendingSystemAction: String? = null

        /** 当前线路名（Flutter 连接成功后告知），用于连接通知与快捷开关副标题 */
        @Volatile
        var activeNodeName: String? = null

        @JvmStatic
        fun emitNetworkChanged() {
            mainHandler.post {
                try {
                    methodChannel?.invokeMethod("networkChanged", null)
                } catch (_: Throwable) {
                }
            }
        }

        /** 快捷开关 / 通知启动 App 并自动连接 */
        @JvmStatic
        fun connectIntent(ctx: Context): Intent =
            Intent(ctx, MainActivity::class.java).apply {
                putExtra(EXTRA_ACTION, "connect")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }

        /**
         * 快捷开关 / 通知上的「断开」：优先交给 Flutter（界面状态、计时器、健康检查一起收尾），
         * 3 秒后 VPN 仍在运行（Flutter 未响应）则原生直接断开。
         */
        @JvmStatic
        fun requestDisconnect(ctx: Context) {
            mainHandler.post {
                val act = activityRef?.get()
                val ch = methodChannel
                if (act != null && ch != null) {
                    try {
                        ch.invokeMethod("systemAction", "disconnect")
                    } catch (_: Throwable) {
                    }
                    mainHandler.postDelayed({
                        if (FluxVpnService.isVpnRunning) {
                            val a = activityRef?.get()
                            if (a != null) {
                                Thread { a.disconnectV2ray() }.start()
                            } else {
                                FluxVpnService.stopDirectly()
                            }
                        }
                    }, 3000)
                } else {
                    // 没有界面（理论上 VPN 不会在 Activity 销毁后继续运行）：直接停 VPN
                    FluxVpnService.stopDirectly()
                }
            }
        }
    }

    private fun handleSystemIntent(src: Intent?) {
        val i: Intent = src ?: return
        val action: String = i.getStringExtra(EXTRA_ACTION) ?: return
        i.removeExtra(EXTRA_ACTION) // 旋转 / 重建时不重复触发
        pendingSystemAction = action
        try {
            methodChannel?.invokeMethod("systemAction", action)
        } catch (_: Throwable) {
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSystemIntent(intent)
    }

    private fun requestNotificationPermissionOnce(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return false
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return false
        val prefs = getSharedPreferences("dzy_native", Context.MODE_PRIVATE)
        if (prefs.getBoolean("notif_perm_asked", false)) return false
        prefs.edit().putBoolean("notif_perm_asked", true).apply()
        return try {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION)
            true
        } catch (_: Throwable) {
            false
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            FluxVpnService.refreshNotification()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        activityRef = java.lang.ref.WeakReference(this)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // ── v1.3.0：快捷开关 / 通知 / 网络切换 ──
                "takeSystemAction" -> {
                    val a = pendingSystemAction
                    pendingSystemAction = null
                    result.success(a)
                }
                "netChangedAgoMs" -> {
                    val t = FluxVpnService.lastNetworkChangeAt
                    result.success(if (t == 0L) -1L else SystemClock.elapsedRealtime() - t)
                }
                "setActiveNode" -> {
                    activeNodeName = call.argument<String>("name")
                    FluxVpnService.refreshNotification()
                    TileBridge.refresh(applicationContext)
                    result.success(true)
                }
                "requestNotificationPermission" -> {
                    result.success(requestNotificationPermissionOnce())
                }
                "connect" -> {
                    val configJson = call.argument<String>("config")
                    if (configJson == null) {
                        result.error("INVALID_ARGUMENT", "Config is null", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val success = connectV2ray(configJson)
                            mainHandler.post { result.success(success) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("CONNECTION_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                "disconnect" -> {
                    Thread {
                        try {
                            disconnectV2ray()
                            mainHandler.post { result.success(true) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("DISCONNECT_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                "isConnected" -> {
                    result.success(FluxVpnService.isVpnRunning)
                }
                // ── v1.3.0：VPN 授权状态（用于「验证网络」阶段区分「等待授权」与「被拒绝」）──
                "vpnState" -> {
                    result.success(mapOf(
                        "running" to FluxVpnService.isVpnRunning,
                        "pending" to vpnPermissionPending,
                        "denied" to vpnPermissionDenied,
                    ))
                }
                // ── v1.3.0：本机流量累计（服务器为时长套餐，不统计每用户流量）──
                "usageStats" -> {
                    result.success(UsageStore.snapshot(applicationContext))
                }
                "usageBeginSession" -> {
                    UsageStore.beginSession(applicationContext)
                    result.success(true)
                }
                "usageReset" -> {
                    UsageStore.resetTotal(applicationContext)
                    result.success(true)
                }
                // ── v1.3.0：轻量环境检测（只提示，不阻断）──
                "securityStatus" -> {
                    Thread {
                        val r = try { SecurityCheck.collect(applicationContext) } catch (t: Throwable) { mapOf("error" to (t.message ?: "")) }
                        mainHandler.post { result.success(r) }
                    }.start()
                }
                // ── v1.2.0 实时网速：hev-socks5-tunnel 自带的 TUN 计数器（进程内 JNI，零额外开销）──
                "trafficStats" -> {
                    result.success(readTrafficStats())
                }
                // ── v1.2.0 应用内更新 ──
                "supportedAbis" -> {
                    result.success(Build.SUPPORTED_ABIS.toList())
                }
                "sha256File" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGUMENT", "path is null", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val hex = sha256Of(File(path))
                            mainHandler.post { result.success(hex) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("SHA_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "canInstallPackages" -> {
                    result.success(canInstallPackages())
                }
                "openInstallSettings" -> {
                    result.success(openInstallSettings())
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGUMENT", "path is null", null)
                        return@setMethodCallHandler
                    }
                    result.success(installApk(File(path)))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STATUS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    vpnStatusSink = events
                    events?.success(FluxVpnService.isVpnRunning)
                }

                override fun onCancel(arguments: Any?) {
                    vpnStatusSink = null
                }
            })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        splashScreen.setKeepOnScreenCondition { false }
        window.setBackgroundDrawableResource(R.color.launch_background)

        super.onCreate(savedInstanceState)

        // 沉浸式：内容延伸到透明状态栏下方（Flutter 侧按安全区留白）
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        )

        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.parseColor("#05070F")
        handleSystemIntent(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (activityRef?.get() === this) {
            activityRef = null
            methodChannel = null
        }
        disconnectV2ray()
    }

    // ───────────────────────── v1.2.0：实时网速 ─────────────────────────
    /**
     * 返回 TUN 累计字节数：{"up": 上行, "down": 下行, "src": "hev"|"uid"}，未连接返回 null。
     * 主方案：hev-socks5-tunnel 的 TProxyGetStats()（与 VPN 服务同进程，读几个计数器，开销可忽略）。
     *   [0]=tx_packets [1]=tx_bytes(从 TUN 读出 = 上行) [2]=rx_packets [3]=rx_bytes(写入 TUN = 下行)
     * 兜底：本应用 UID 的 TrafficStats（xray 子进程与 tun2socks 都属于本 UID）。
     */
    private fun readTrafficStats(): Map<String, Any>? {
        if (!FluxVpnService.isVpnRunning) return null
        try {
            val arr = hev.htproxy.TProxyService.TProxyGetStats()
            if (arr != null && arr.size >= 4) {
                return mapOf("up" to arr[1], "down" to arr[3], "src" to "hev")
            }
        } catch (t: Throwable) {
            Log.w(TAG, "TProxyGetStats unavailable: ${t.message}")
        }
        val uid = AndroidProcess.myUid()
        val rx = TrafficStats.getUidRxBytes(uid)
        val tx = TrafficStats.getUidTxBytes(uid)
        if (rx == TrafficStats.UNSUPPORTED.toLong() || tx == TrafficStats.UNSUPPORTED.toLong()) return null
        return mapOf("up" to tx, "down" to rx, "src" to "uid")
    }

    // ───────────────────────── v1.2.0：应用内更新 ─────────────────────────
    private fun sha256Of(file: File): String {
        val md = java.security.MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n <= 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else true
    }

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (e2: Exception) {
                Log.e(TAG, "open install settings failed: ${e2.message}")
                false
            }
        }
    }

    /** 调起系统安装器（用户需轻点一次「安装」）。返回 started / need_permission / failed */
    private fun installApk(file: File): String {
        if (!file.exists()) return "failed"
        if (!canInstallPackages()) return "need_permission"
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "started"
        } catch (e: Exception) {
            Log.e(TAG, "install apk failed: ${e.message}")
            "failed"
        }
    }

    /**
     * 获取 Xray 可执行文件路径
     * 1. 尝试从 nativeLibraryDir 获取 (libxray.so)
     * 2. 如果失败，尝试从 Assets 复制到 filesDir 并赋予执行权限
     */
    private fun getXrayExecutable(): String? {
        // 1. 尝试从 nativeLibraryDir 查找
        val libDir = applicationInfo.nativeLibraryDir
        val libFile = File(libDir, "libxray.so")
        if (libFile.exists()) {
            Log.d(TAG, "Found Xray in nativeLibraryDir: ${libFile.absolutePath}")
            return libFile.absolutePath
        }

        // 2. 尝试查找含有 xray 的文件 (针对 weird naming)
        val dir = File(libDir)
        val files = dir.listFiles { _, name -> name.contains("xray") }
        if (files != null && files.isNotEmpty()) {
            Log.d(TAG, "Found Xray (fuzzy) in nativeLibraryDir: ${files[0].absolutePath}")
            return files[0].absolutePath
        }

        // 3. 都没有，尝试从 Assets 复制到 filesDir
        Log.w(TAG, "Xray not found in nativeLibraryDir, trying to copy from assets...")
        val internalBin = File(filesDir, "libxray.so")
        
        // 尝试从 assets 复制 "libxray.so" (Flutter assets mapping needed? No, binary stays in Android assets/libs)
        // 注意：这里需要确保 binary 确实在 android assets 里。
        // 由于用户说 assets/bin 是 Flutter assets，所以 binary 必须通过 nativeLibraryDir 找到最稳。
        // 这里保留 fallback 逻辑，假设用户手动放了 assets
        if (copyBinaryFromAssets("libxray.so", internalBin)) {
             return internalBin.absolutePath
        }
        
        if (copyBinaryFromAssets("xray-android-arm64-v8a", internalBin)) {
             return internalBin.absolutePath
        }

        Log.e(TAG, "Xray binary not found in libs or assets!")
        return null
    }

    private fun copyBinaryFromAssets(assetName: String, targetFile: File): Boolean {
        try {
            assets.open(assetName).use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }
            if (!targetFile.setExecutable(true, true)) {
                Runtime.getRuntime().exec("chmod 700 ${targetFile.absolutePath}").waitFor()
            }
            return true
        } catch (e: Exception) {
            return false
        }
    }

    private fun connectV2ray(configJson: String): Boolean {
        return try {
            if (isV2rayRunning || xrayProcess != null) {
                disconnectV2ray()
                // 等旧进程真正退出、释放端口（最多 1.5 秒），而不是固定等 500ms
                val t0 = System.currentTimeMillis()
                while (System.currentTimeMillis() - t0 < 1500) {
                    val free = try {
                        java.net.ServerSocket().use { ss ->
                            ss.reuseAddress = true
                            ss.bind(java.net.InetSocketAddress("127.0.0.1", 10808))
                        }
                        true
                    } catch (_: Exception) {
                        false
                    }
                    if (free) break
                    Thread.sleep(50)
                }
            }

            val fullConfigObj = JSONObject(configJson)
            
            // 兼容旧逻辑：如果直接传的是 Outbound Config (没有 inbound/outbound 包装)，则当作 old style
            val outboundConfig = if (fullConfigObj.has("outbound")) {
                fullConfigObj.getJSONObject("outbound")
            } else {
                fullConfigObj
            }
            
            val routingMode = fullConfigObj.optString("routingMode", "rule")
            val routingRules = fullConfigObj.optJSONArray("routingRules")

            val protocol = outboundConfig.optString("protocol", "")
            currentProtocol = protocol
            
            Log.d(TAG, "Connecting protocol: $protocol, Mode: $routingMode")
            
            return connectXray(outboundConfig, routingMode, routingRules)

        } catch (e: Exception) {
            Log.e(TAG, "Error connecting: ${e.message}")
            e.printStackTrace()
            false
        }
    }
    
    // Old Hysteria2 methods removed (unified into Xray)
    
    /**
     * 使用 Xray 连接（非 Hysteria2 协议）
     */
    private fun connectXray(outboundConfig: JSONObject, routingMode: String, customRules: org.json.JSONArray?): Boolean {
        // 1. 获取可执行文件
        val executablePath = getXrayExecutable()
        if (executablePath == null) {
            Log.e(TAG, "Xray binary not found!")
            return false
        }

        // 2. 生成配置文件
        val configDir = filesDir.absolutePath
        val configFile = File(configDir, "config.json")
        val fullConfig = buildV2rayConfig(outboundConfig, routingMode, customRules)
        
        // 写入配置文件
        FileOutputStream(configFile).use { 
            it.write(fullConfig.toByteArray()) 
        }

        // 3. 启动进程
        Log.d(TAG, "Starting Xray process: $executablePath -c ${configFile.absolutePath}")
        val pb = ProcessBuilder(executablePath, "-c", configFile.absolutePath)
        pb.directory(filesDir)
        // 设置环境变量指向 dat 目录
        val env = pb.environment()
        env["xray.location.asset"] = configDir
        
        xrayProcess = pb.start()
        
        // 4. 读取日志（可选，防止 buffer 满）
        Thread {
            try {
                val reader = BufferedReader(InputStreamReader(xrayProcess!!.inputStream))
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    Log.d("XrayCore", line ?: "")
                }
            } catch (e: Exception) {
                // Ignore exceptions when process is destroyed
                Log.d("XrayCore", "Process output stream closed")
            }
        }.start()
        
        Thread {
            try {
                val reader = BufferedReader(InputStreamReader(xrayProcess!!.errorStream))
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    Log.e("XrayCore", line ?: "")
                }
            } catch (e: Exception) {
                // Ignore exceptions when process is destroyed
                 Log.d("XrayCore", "Process error stream closed")
            }
        }.start()

        // 等待启动：轮询探测入站 10810 是否已监听（通常 100–300ms），最多 2 秒；
        // 比固定 sleep(500) 更快，也保证随后的出网验证不会撞上「端口还没开」
        val proc = xrayProcess!!
        val waitStart = System.currentTimeMillis()
        while (System.currentTimeMillis() - waitStart < 2000 && proc.isAlive) {
            val up = try {
                java.net.Socket().use { s ->
                    s.connect(java.net.InetSocketAddress("127.0.0.1", 10810), 100)
                }
                true
            } catch (_: Exception) {
                false
            }
            if (up) break
            Thread.sleep(50)
        }
        
        if (proc.isAlive) {
            isV2rayRunning = true
            requestVpnPermission()
            return true
        } else {
            Log.e(TAG, "Xray process died immediately")
            return false
        }
    }

    fun disconnectV2ray() {
        try {
            stopVpnService()
            
            // 停止 Xray 进程
            if (xrayProcess != null) {
                xrayProcess!!.destroy()
                xrayProcess = null
            }
            

            
            isV2rayRunning = false
            currentProtocol = ""
        } catch (e: Exception) {
            Log.e(TAG, "Error disconnecting: ${e.message}")
        }
    }

    private fun requestVpnPermission() {
        val intent = VpnService.prepare(this)
        vpnPermissionDenied = false
        if (intent != null) {
            vpnPermissionPending = true
            mainHandler.post {
                try {
                    startActivityForResult(intent, REQUEST_VPN_PERMISSION)
                } catch (e: Exception) {
                    Log.e(TAG, "request VPN permission failed: ${e.message}")
                    vpnPermissionPending = false
                    vpnPermissionDenied = true
                }
            }
        } else {
            vpnPermissionPending = false
            startVpnService()
        }
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_PERMISSION) {
            vpnPermissionPending = false
            if (resultCode == RESULT_OK) {
                startVpnService()
            } else {
                vpnPermissionDenied = true
            }
        }
    }
    
    private fun startVpnService() {
        try {
            val intent = Intent(this, FluxVpnService::class.java).apply {
                action = FluxVpnService.ACTION_START
            }
            startService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting VPN service: ${e.message}")
        }
    }
    
    private fun stopVpnService() {
        try {
            val intent = Intent(this, FluxVpnService::class.java).apply {
                action = FluxVpnService.ACTION_STOP
            }
            startService(intent)
            stopService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping VPN service: ${e.message}")
            // App 在后台时 startService 可能被系统拒绝（快捷开关 / 通知断开）：直接停止同进程内的服务
            if (FluxVpnService.isVpnRunning) FluxVpnService.stopDirectly()
        }
    }

    private fun buildV2rayConfig(outbound: JSONObject, routingMode: String, customRules: org.json.JSONArray?): String {
        val config = JSONObject()
        ensureStreamSettings(outbound)
        
        // 1. Log
        val log = JSONObject().put("loglevel", "warning")
        config.put("log", log)
        
        // 2. Stats
        config.put("stats", JSONObject())
        
        // 3. Policy
        val policy = JSONObject()
        val levels = JSONObject().put("0", JSONObject()
            .put("handshake", 4)
            .put("connIdle", 300)
            .put("uplinkOnly", 2)
            .put("downlinkOnly", 5)
            .put("statsUserUplink", true)
            .put("statsUserDownlink", true)
            .put("bufferSize", 4)
        )
        val system = JSONObject()
            .put("statsInboundUplink", true)
            .put("statsInboundDownlink", true)
            .put("statsOutboundUplink", true)
            .put("statsOutboundDownlink", true)
        policy.put("levels", levels)
        policy.put("system", system)
        config.put("policy", policy)
        
        // 4. DNS
        val dns = JSONObject()
        dns.put("queryStrategy", "UseIPv4")
        val dnsServers = org.json.JSONArray()
        
        // Domestic DNS
        val domesticDns = JSONObject()
        domesticDns.put("address", "223.5.5.5")
        
        val domesticDomains = org.json.JSONArray()
        domesticDomains.put("geosite:cn")
        
        // Add Server Address to Domestic DNS
        val settings = outbound.optJSONObject("settings")
        if (settings != null && settings.has("address")) {
            val serverAddress = settings.getString("address")
            if (serverAddress.isNotEmpty()) {
                domesticDomains.put(serverAddress)
            }
        }
        
        domesticDns.put("domains", domesticDomains)
        domesticDns.put("expectIPs", org.json.JSONArray().put("geoip:cn"))
        dnsServers.put(domesticDns)

        // Foreign DNS
        dnsServers.put("8.8.8.8")
        dnsServers.put("1.1.1.1")
        dnsServers.put("localhost")
        
        dns.put("servers", dnsServers)
        config.put("dns", dns)
        
        // 5. Inbounds
        val inbounds = org.json.JSONArray()
        val socksInbound = JSONObject()
        socksInbound.put("tag", "socks")
        socksInbound.put("port", 10808)
        socksInbound.put("listen", "127.0.0.1")
        socksInbound.put("protocol", "socks")
        socksInbound.put("settings", JSONObject().put("auth", "noauth").put("udp", true))
        socksInbound.put("sniffing", JSONObject().put("enabled", true)
            .put("destOverride", org.json.JSONArray().put("http").put("tls").put("quic")))
        inbounds.put(socksInbound)
        
        val httpInbound = JSONObject()
        httpInbound.put("tag", "http")
        httpInbound.put("port", 10809)
        httpInbound.put("listen", "127.0.0.1")
        httpInbound.put("protocol", "http")
        httpInbound.put("sniffing", JSONObject().put("enabled", true)
            .put("destOverride", org.json.JSONArray().put("http").put("tls").put("quic")))
        inbounds.put(httpInbound)
        
        // v1.3.0：出网探测专用入站（仅本机回环），路由第一条规则强制走 proxy 出站，
        // 不受智能分流 / 远程规则影响，用于验证所选线路是否真的能访问外网
        val probeInbound = JSONObject()
        probeInbound.put("tag", "probe")
        probeInbound.put("port", 10810)
        probeInbound.put("listen", "127.0.0.1")
        probeInbound.put("protocol", "http")
        inbounds.put(probeInbound)

        config.put("inbounds", inbounds)
        
        // 6. Routing
        val routing = JSONObject()
        routing.put("domainStrategy", "IPIfNonMatch")
        val rules = org.json.JSONArray()
        rules.put(JSONObject().put("type", "field").put("inboundTag", org.json.JSONArray().put("probe")).put("outboundTag", "proxy"))
        
        // 6.1 Bootstrap Direct
        if (settings != null && settings.has("address")) {
            val serverAddress = settings.getString("address")
            if (serverAddress.isNotEmpty()) {
                rules.put(JSONObject().put("type", "field").put("outboundTag", "direct").put("domain", org.json.JSONArray().put(serverAddress)))
            }
        }
        
        // 6.2 DNS Loop Break
        rules.put(JSONObject().put("type", "field").put("outboundTag", "direct").put("ip", org.json.JSONArray().put("8.8.8.8").put("1.1.1.1")))
        
        // 6.3 Mode Handling
        if (routingMode == "global") {
            // Global Mode: Only bypass private/LAN
             rules.put(JSONObject().put("type", "field").put("outboundTag", "direct").put("ip", org.json.JSONArray().put("geoip:private")))
             rules.put(JSONObject().put("type", "field").put("outboundTag", "direct").put("domain", org.json.JSONArray().put("geosite:private")))
        } else {
            // Rule Mode
            var hasCustomRules = false
            if (customRules != null && customRules.length() > 0) {
                 Log.d(TAG, "Applying ${customRules.length()} custom routing rules")
                 for (i in 0 until customRules.length()) {
                     rules.put(customRules.getJSONObject(i))
                 }
                 hasCustomRules = true
            }
            
            // Fallback default rules if no custom rules provided
            if (!hasCustomRules) {
                Log.d(TAG, "Applying default routing rules")
                 rules.put(JSONObject().put("type", "field").put("outboundTag", "direct").put("ip", org.json.JSONArray().put("geoip:private")))
                 rules.put(JSONObject().put("type", "field").put("outboundTag", "direct").put("domain", org.json.JSONArray().put("geosite:private")))
                 
                val geoip = File(filesDir, "geoip.dat")
                if (geoip.exists()) {
                    rules.put(JSONObject().put("type", "field").put("outboundTag", "direct").put("domain", org.json.JSONArray().put("geosite:cn")))
                    rules.put(JSONObject().put("type", "field").put("outboundTag", "direct").put("ip", org.json.JSONArray().put("geoip:cn")))
                }
            }
        }

        // Final Catch-all Proxy
        rules.put(JSONObject().put("type", "field").put("outboundTag", "proxy").put("network", "tcp,udp"))
        
        routing.put("rules", rules)
        config.put("routing", routing)
        
        // 7. Outbounds
        val outbounds = org.json.JSONArray()
        if (!outbound.has("tag")) outbound.put("tag", "proxy")
        outbounds.put(outbound)
        
        // Xray v26：freedom.settings.domainStrategy 已弃用，改用 streamSettings.sockopt.domainStrategy
        outbounds.put(JSONObject().put("protocol", "freedom").put("tag", "direct")
            .put("streamSettings", JSONObject().put("sockopt", JSONObject().put("domainStrategy", "UseIP"))))
        outbounds.put(JSONObject().put("protocol", "blackhole").put("tag", "block"))
        
        config.put("outbounds", outbounds)
        
        return config.toString()
    }
    
    private fun ensureStreamSettings(outbound: JSONObject) {
        val protocol = outbound.optString("protocol", "")
        if (protocol == "trojan") {
            var streamSettings = outbound.optJSONObject("streamSettings")
            if (streamSettings == null) {
                streamSettings = JSONObject()
                outbound.put("streamSettings", streamSettings)
            }
            if (!streamSettings.has("security")) streamSettings.put("security", "tls")
            if (!streamSettings.has("network")) streamSettings.put("network", "tcp")
            if (!streamSettings.has("tlsSettings")) streamSettings.put("tlsSettings", JSONObject())
        }
    }
}
