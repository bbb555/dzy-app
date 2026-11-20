import 'dart:async';
import '../services/diag_log.dart';
import 'diag_screen.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../services/account_session.dart';
import '../services/connection_supervisor.dart';
import '../services/egress_probe.dart';
import '../services/latency_test_service.dart';
import '../services/usage_service.dart';
import '../services/daily_usage_service.dart';
import '../security/security_monitor.dart';
import '../services/subscription_service.dart';

import '../services/unified_vpn_service.dart';
import '../services/v2ray_service.dart';
import '../services/tray_service.dart';
import '../services/remote_config_service.dart';
import '../services/update_service.dart';
import '../services/user_data_service.dart';
import '../models/server_node.dart';
import '../utils/node_region.dart';
import '../theme/app_colors.dart';
import 'account_screen.dart';
import 'home_dashboard.dart';
import '../widgets/dz_ui.dart';
import '../widgets/glass_nav_bar.dart';
import '../widgets/desktop_nav.dart';
import '../widgets/node_picker_sheet.dart';
import '../widgets/update_dialog.dart';

import 'package:window_manager/window_manager.dart';

class RootShell extends StatefulWidget {
  final VoidCallback onLogout;
  const RootShell({super.key, required this.onLogout});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with WindowListener, WidgetsBindingObserver {
  final _subscriptionService = SubscriptionService();
  final _vpnService = UnifiedVpnService.instance;
  final _trayService = TrayService.instance;

  ConnPhase _phase = ConnPhase.idle;
  String _statusMessage = '';
  int _index = 0;
  final int _accountReload = 0;
  bool _isConnecting = false;
  bool _isInitializing = true; // 全局初始化状态

  // 当前线路展示
  ServerNode? _activeNode;
  String? _activeName;
  bool _autoMode = true;

  /// v1.5.15：视频优先开关（自动选择时优先挑大带宽线路）。持久化于
  /// [LatencyTestService.videoFirstPrefKey]，默认关闭。
  bool _videoFirst = false;

  // v1.5.8：连接/切换历史（内存态，最多 20 条）
  final List<_SwitchRecord> _switchHistory = [];

  /// 记录一条连接/切换事件（新记录在最前）
  void _logSwitch(String kind, String text) {
    _switchHistory.insert(0, _SwitchRecord(DateTime.now(), kind, text));
    if (_switchHistory.length > 20) {
      _switchHistory.removeRange(20, _switchHistory.length);
    }
  }

  // 订阅定时刷新：前台或已连接时每 10 分钟检查一次，缓存超过 1 小时才真正请求服务器
  Timer? _subTimer;
  bool _foreground = true;

  // v1.3.0：真实出网验证 / 健康检查 / 自动切换
  final EgressProbe _probe = EgressProbe();
  late final HealthMonitor _health = HealthMonitor(
    probeEgress: () => _probeEgress(timeout: const Duration(seconds: 8)),
    probeLocal: _probeLocal,
    onVerdict: _onHealthVerdict,
    sinceNetworkChange: () => _probeSupported
        ? V2rayService().sinceNetworkChange()
        : Future.value(null),
  );
  final FailoverBudget _failoverBudget = FailoverBudget();
  bool _supervising = false;
  ConnectionSupervisor? _supervisor;

  // Lazy loading: 跟踪哪些页面已经被访问
  final Set<int> _visitedIndices = {0}; // 默认加载首页

  // 判断是否是桌面平台
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  StreamSubscription<String>? _systemSub;
  String? _pushedNodeName;

  @override
  void initState() {
    super.initState();
    _vpnService.statusStream.listen(_onVpnStatusChanged);
    if (_probeSupported) {
      _systemSub = V2rayService.systemEvents.listen(_onSystemEvent);
    }
    WidgetsBinding.instance.addObserver(this);

    // 统一初始化流程
    _initApp();

    // 初始化窗口监听
    if (_isDesktop) {
      windowManager.addListener(this);
      _initWindow();
    }
  }

  /// 统一初始化：只等本地就能完成的部分（托盘 / VPN 状态），网络相关全部放到后台，首屏不再被订阅刷新卡住
  Future<void> _initApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoMode = !(prefs.getBool('node_manual_selected') ?? false);
      _activeName = prefs.getString('last_node_name');
      // v1.5.15：视频优先开关（默认关闭）
      _videoFirst =
          prefs.getBool(LatencyTestService.videoFirstPrefKey) ?? false;

      // 1. 基础服务 (Tray)
      await _initTray();

      // 2. 检查 VPN 状态
      await _checkInitialStatus();
    } catch (e) {
      debugPrint('Initialization failed: $e');
    }
    if (mounted) setState(() => _isInitializing = false);
    _syncSubscriptionTimer();
    // 由快捷开关冷启动拉起（「打开并连接」）：初始化完成后执行
    if (_probeSupported) {
      final pending = await V2rayService().takePendingSystemAction();
      if (pending != null) _onSystemEvent(pending);
    }
    unawaited(_warmUp());
    // v1.3.0：轻量环境检测（只提示，不阻断），结果用于「我的」页安全提示与 TLS 固定失败策略
    SecurityMonitor.instance.signals();
    UsageService.instance.refresh();
    // 启动后稍等再检查更新（最多每 6 小时一次），不打扰首屏
    Future.delayed(const Duration(seconds: 4), () => _autoCheckUpdate());
  }

  /// 退出登录：先断开 VPN、停掉健康检查，再清空订阅 / 测速缓存与线路选择，避免下一个账号沿用
  Future<void> _logoutCleanup() async {
    _cancelRequested = true;
    _supervisor?.cancel();
    _health.stop();
    _subTimer?.cancel();
    _subTimer = null;
    await AccountSession.logout(
      isTunnelUp: _vpnService.isConnected,
      disconnect: () => _vpnService.disconnect(),
      uiSaysConnected: _phase.online || _phase.busy,
    );
    _activeNode = null;
    _activeName = null;
    _pushedNodeName = null;
    widget.onLogout();
  }

  /// 后台预热：域名 → 订阅（缓存未过期时不走网络）→ 用缓存延迟 / 后台测速，让第一次点连接即可直接连最快线路
  Future<void> _warmUp() async {
    try {
      await RemoteConfigService().getActiveDomain();
      unawaited(UserDataService().getNotices().then((_) {}, onError: (_) {}));
      final nodes = await _subscriptionService.fetchNodes();
      if (nodes.isEmpty || !mounted) return;
      await LatencyCache.instance.load();
      final fresh = LatencyCache.instance
          .apply(nodes, maxAge: const Duration(minutes: 10), onlyReachable: true);
      // 缓存太旧才测速；已在连接中时不抢带宽
      if (fresh == 0 && !_phase.busy) {
        await LatencyTestService().testAll(nodes, concurrency: 8);
      }
    } catch (e) {
      debugPrint('[RootShell] warm-up failed: $e');
    }
  }

  // ── 订阅自动刷新 ─────────────────────────────────────
  bool get _shouldTickSubscription => _foreground || _phase.online;

  void _syncSubscriptionTimer() {
    if (_shouldTickSubscription) {
      _subTimer ??= Timer.periodic(const Duration(minutes: 10), (_) {
        _subscriptionService.refreshIfStale();
      });
    } else {
      _subTimer?.cancel();
      _subTimer = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    _health.setForeground(fg);
    _syncSubscriptionTimer();
    if (fg && !_isInitializing) {
      // 回到前台：缓存过期则刷新订阅；检查更新（6 小时节流）
      _subscriptionService.refreshIfStale();
      _autoCheckUpdate();
    }
  }

  bool _updatePrompting = false;

  Future<void> _autoCheckUpdate() async {
    if (!mounted || _updatePrompting || !Platform.isAndroid) return;
    try {
      final info = await UpdateService.instance.check(manual: false);
      if (info == null || !mounted) return;
      if (!info.mustUpdate && !await UpdateService.instance.shouldPrompt(info)) {
        return;
      }
      if (!mounted) return;
      _updatePrompting = true;
      await showUpdateDialog(context, info);
      // 点遮罩关闭也算「稍后」：同一版本 24 小时内不再自动弹出
      if (!info.mustUpdate) await UpdateService.instance.snooze(info);
    } catch (e) {
      debugPrint('[Update] auto check failed: $e');
    } finally {
      _updatePrompting = false;
    }
  }

  Future<void> _initWindow() async {
    await windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _systemSub?.cancel();
    _subTimer?.cancel();
    _supervisor?.cancel();
    _health.stop();
    if (_isDesktop) {
      windowManager.removeListener(this);
      // 退出时确保断开，防止代理残留
      _vpnService.disconnect();
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_isDesktop) {
      bool isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose) {
        await windowManager.hide();
      }
    }
  }

  Future<void> _initTray() async {
    if (_isDesktop) {
      await _trayService.init(
        onConnect: _toggleConnection,
        onDisconnect: _toggleConnection,
        onShowWindow: () async {
          await windowManager.show();
          await windowManager.focus();
        },
        onQuit: () async {
          // 彻底退出前先断开连接，防止代理残留
          if (_phase.online || _phase.busy) {
            debugPrint('[RootShell] Quitting... Disconnecting VPN...');
            await _vpnService.disconnect();
          }

          await windowManager.setPreventClose(false);
          exit(0);
        },
      );
    }
  }

  Future<void> _checkInitialStatus() async {
    final isConnected = await _vpnService.isConnected();
    if (mounted && isConnected) {
      // VPN 仍在运行（App 被重新打开）：不直接宣称已连接，先验证真实出网
      _verifyExistingTunnel();
    }
  }

  void _onVpnStatusChanged(bool isConnected) {
    if (!mounted) return;
    // 连接 / 切换流程中隧道会反复起停，状态由流程自己负责，这里不插手
    if (_supervising || _isConnecting) return;
    if (!isConnected && (_phase.online || _phase == ConnPhase.verifying)) {
      // VPN 被系统 / 其它 VPN 应用关闭（不是用户在本 App 里点的断开）
      _health.stop();
      _failoverBudget.reset();
      _setPhase(ConnPhase.idle, 'VPN 已被系统或其他 VPN 应用关闭，轻触重新连接');
    } else if (isConnected && !_phase.online && !_phase.busy) {
      _verifyExistingTunnel();
    }
  }

  void _switchTab(int newIndex) {
    if (newIndex == _index) return;
    setState(() {
      _index = newIndex;
      _visitedIndices.add(newIndex);
    });
  }

  void _setPhase(ConnPhase p, String msg) {
    if (!mounted) return;
    setState(() {
      _phase = p;
      _statusMessage = msg;
    });
    _syncSubscriptionTimer();
    _pushNodeToNative();
  }

  /// 连接通知 / 快捷开关显示的当前线路名（去掉会变化的实测速率）
  void _pushNodeToNative() {
    if (!_probeSupported || !_phase.online) return;
    final n = _activeName == null ? null : NodeLabel.stableKey(_activeName!);
    if (n == _pushedNodeName) return;
    _pushedNodeName = n;
    V2rayService().setActiveNodeName(n);
  }

  /// 快捷开关 / 连接通知「断开」/ 网络切换
  void _onSystemEvent(String e) {
    if (!mounted) return;
    switch (e) {
      case 'network':
        // Wi-Fi ↔ 移动数据切换：几秒后复查一次（健康检查对切换期间的失败有宽限，不会误切线路）
        if (_phase.online) _health.kick();
        break;
      case 'connect':
        if (_isInitializing || _isConnecting || _phase.online) return;
        _toggleConnection();
        break;
      case 'disconnect':
        if (_isConnecting) {
          if (_phase == ConnPhase.connecting ||
              _phase == ConnPhase.verifying ||
              _phase == ConnPhase.switching) {
            _cancelConnecting();
          }
        } else if (_phase.online || _phase == ConnPhase.verifying) {
          _toggleConnection();
        } else {
          // 界面认为未连接但隧道还在（异常状态）：直接关掉
          _vpnService.disconnect();
        }
        break;
    }
  }

  // ── v1.3.0：真实出网验证 + 自动切换 ─────────────────────────
  bool get _probeSupported => !kIsWeb && Platform.isAndroid;

  /// 最近一次出网探测的实时延迟（ms）。健康检查周期刷新，供首页「实时」显示。
  int? _liveLatencyMs;

  /// v1.5.9：本轮连接是否已经做过预热测量（每次只做一次）
  bool _warmPending = false;

  Future<ProbeResult> _probeEgress({Duration? timeout}) async {
    if (!_probeSupported) return const ProbeResult.skipped();
    final t = timeout ?? const Duration(seconds: 6);
    final r = await _probe.checkEgress(timeout: t);
    // 探测成功即刷新「实时延迟」；失败保持上次值（UI 上以颜色降级提示）
    if (r.ok && r.ms != null && mounted) {
      if (_liveLatencyMs == null) {
        // v1.5.9（队长定版）：本轮第一发是刚建连的冷值（远端 DNS + 建连都算在里面），
        // 只当连通性判定用，不显示；先测一个热态值，首页出现的第一个数就是线路真实水平。
        if (!_warmPending && _phase.online) {
          _warmPending = true;
          unawaited(_refreshWarmLatency(t));
        }
      } else if (_liveLatencyMs != r.ms) {
        setState(() => _liveLatencyMs = r.ms);
      }
    }
    return r;
  }

  /// v1.5.9：预热后测一次线路延迟并作为首页显示值（每次连接只做一次）
  Future<void> _refreshWarmLatency(Duration t) async {
    try {
      final w = await _probe.measureWarm(timeout: t);
      if (!mounted || !w.ok || w.ms == null) return;
      setState(() => _liveLatencyMs = w.ms);
    } catch (_) {
      // 测量失败不影响连接状态
    } finally {
      _warmPending = false;
    }
  }

  Future<ProbeResult> _probeLocal() => _probeSupported
      ? _probe.checkLocalNetwork()
      : Future.value(const ProbeResult.skipped());

  /// 等待 VpnService 接口建立。首次连接系统会弹出 VPN 授权框，最多等 60 秒。
  Future<bool> _waitTunnelUp() async {
    final sw = Stopwatch()..start();
    var hinted = false;
    while (sw.elapsed < const Duration(seconds: 60)) {
      if (_cancelRequested) return false;
      final st = await _vpnService.vpnState();
      if (st['running'] == true) return true;
      if (st['denied'] == true) return false;
      final pending = st['pending'] == true;
      if (pending && !hinted) {
        hinted = true;
        _setPhase(ConnPhase.verifying, '请在系统弹窗中允许 VPN 连接');
      }
      // 没有授权弹窗时，接口一般 1 秒内建立；8 秒还没起来视为失败
      if (!pending && sw.elapsed > const Duration(seconds: 8)) return false;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  ConnectionSupervisor _newSupervisor() => ConnectionSupervisor(
        connect: (n) => _vpnService.connect(n),
        disconnect: () async {
          await _vpnService.disconnect();
        },
        waitTunnelUp: _waitTunnelUp,
        probeEgress: () => _probeEgress(),
        probeLocal: _probeLocal,
        rank: _rankNodesByLatency,
        refreshNodes: () => _subscriptionService.refreshAfterConnectFailure(),
        // 用户已取消：不再让流程里的进度文案覆盖「正在取消连接…」
        onPhase: (p, m) {
          if (!_cancelRequested) _setPhase(p, m);
        },
      );

  /// 统一连接入口（首次连接 / 手动选线 / 切回自动 / 路由模式切换 / 健康检查自动切换）
  ///
  /// [newSession]：用户主动发起的新连接（本次用量归零）；自动切换为 false。
  /// [switching]：由健康检查触发，界面显示「线路不可用，正在切换」。
  Future<void> _runConnect({
    Set<String> exclude = const {},
    bool switching = false,
    bool newSession = true,
  }) async {
    _health.stop();
    _supervising = true;
    _cancelRequested = false;
    // v1.5.9：新一轮连接，延迟与预热标记清零（不显示上一条线路的数值）
    _liveLatencyMs = null;
    _warmPending = false;
    try {
      _setPhase(switching ? ConnPhase.switching : ConnPhase.connecting,
          switching ? '线路不可用，正在切换…' : '正在获取线路…');

      var nodes = await _subscriptionService.fetchNodes(preferCache: true).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('获取线路超时，请检查网络'),
      );
      // 服务器明确提示套餐到期 / 账户停用：不再用缓存线路硬连，直接告诉用户原因。
      // 用户可能刚在官网续费：先向服务器重新确认一次（手动刷新的 2 分钟防抖仍然有效）
      if (SubscriptionService.isBlockingNotice(SubscriptionService.lastNotice.value)) {
        try {
          nodes = await _subscriptionService
              .fetchNodes(forceRefresh: true)
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
        final notice = SubscriptionService.lastNotice.value;
        if (SubscriptionService.isBlockingNotice(notice)) {
          _setPhase(ConnPhase.error, notice!);
          return;
        }
      }
      if (nodes.isEmpty) {
        _setPhase(ConnPhase.error, '暂无可用线路，请确认订阅是否有效');
        return;
      }
      if (_cancelRequested) {
        _setPhase(ConnPhase.idle, '已取消连接');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastNodeName = prefs.getString('last_node_name');
      // 默认「自动选择」：未手动选过节点时，测速后按延迟从低到高依次尝试
      final manualSelected = prefs.getBool('node_manual_selected') ?? false;
      _autoMode = !manualSelected;
      final manualName =
          manualSelected && lastNodeName != null ? lastNodeName : null;

      if (newSession) await UsageService.instance.beginSession();
      if (!switching) {
        _setPhase(
            ConnPhase.connecting,
            manualName != null
                ? '正在连接 $manualName'
                : '全节点并发测速，锁定最快线路…');
      }

      if (_cancelRequested) {
        _setPhase(ConnPhase.idle, '已取消连接');
        return;
      }
      DiagLog.instance.info('connect',
          '开始连接：候选 ${nodes.length} 条'
          '${manualName != null ? '，指定线路 $manualName' : '，自动选择'}');
      final sup = _supervisor = _newSupervisor();
      final out = await sup.run(nodes,
          manualName: manualName, exclude: exclude, switching: switching);

      if (_cancelRequested) {
        // 取消时 connect() 可能还在途中：结束后确保隧道已关
        try {
          await _vpnService.disconnect();
        } catch (_) {}
        _activeNode = null;
        _setPhase(ConnPhase.idle, '已取消连接');
        return;
      }

      if (out.success && out.node != null) {
        final node = out.node!;
        // 手动线路不可用而临时回落时，保留用户的手动选择（下次仍先试它）
        if (!out.fellBackFromManual) {
          await prefs.setString('last_node_name', node.name);
        }
        _activeNode = node;
        _activeName = node.name;
        // v1.5.8：每日/线路流量统计跟随当前线路
        DailyUsageService.instance
          ..setCurrentLine(NodeLabel.stableKey(node.name))
          ..start();
        _measureActive(node);
        _setPhase(
          ConnPhase.connected,
          out.fellBackFromManual
              ? '所选线路「$manualName」暂时无法访问外网，已自动切换到 ${node.name}'
              : '已连接 ${node.name}',
        );
        // v1.5.8：记录切换历史
        _logSwitch(
          out.fellBackFromManual ? 'auto' : 'ok',
          out.fellBackFromManual
              ? '所选线路不可用，自动切换到「${NodeLabel.stableKey(node.name)}」'
              : '连接「${NodeLabel.stableKey(node.name)}」成功',
        );
        DiagLog.instance.info('connect',
            '连接成功：${node.name}（尝试 ${out.tried.length} 条'
            '${out.fellBackFromManual ? '，已从手动线路回落自动' : ''}）');
        _health.start(firstDelay: const Duration(seconds: 30));
        // Android 13+：首次连接成功后请求一次通知权限（连接通知显示当前线路与「断开」）
        if (_probeSupported) {
          unawaited(V2rayService().requestNotificationPermissionOnce());
        }
        return;
      }

      _activeNode = null;
      switch (out.failure) {
        case ConnFailure.noNodes:
          _setPhase(ConnPhase.error, '暂无可用线路，请确认订阅是否有效');
          break;
        case ConnFailure.vpnDenied:
          // v1.5.12：这一条现在也覆盖「内核能出网但系统没把流量交给隧道」
          // （被别的 VPN/代理类 App 抢占、授权被回收），所以文案写清两种可能
          DiagLog.instance.error('connect', 'VPN 通道未生效（授权被拒或被其它 VPN 抢占）');
          _setPhase(
              ConnPhase.vpnDenied,
              'VPN 通道没生效：请先在弹窗允许授权；若已允许，'
              '请关掉其它 VPN/代理类 App 后重试（可点下方「连接诊断」看原因）');
          break;
        case ConnFailure.offline:
          _setPhase(ConnPhase.offline, '当前网络不可用，请检查 Wi-Fi 或移动数据后重试');
          break;
        case ConnFailure.cancelled:
          _setPhase(ConnPhase.idle, '已取消连接');
          break;
        case ConnFailure.allFailed:
        case ConnFailure.none:
          // 失败后刷新订阅时服务器给出了原因（套餐到期 / 停用 / 过于频繁）：直接显示原因
          final n = SubscriptionService.lastNotice.value;
          if (n != null) {
            _setPhase(SubscriptionService.isBlockingNotice(n) ? ConnPhase.error : ConnPhase.allFailed, n);
            break;
          }
          _logSwitch('fail', '所有线路尝试失败，等待重试');
          DiagLog.instance.error(
              'connect', '全部线路失败：试过 ${out.tried.length} 条线路');
          _setPhase(
            ConnPhase.allFailed,
            manualName != null
                ? '所选线路及备用线路暂时都无法访问外网，已同步最新线路，请稍后重试或换一条线路'
                : '已尝试 ${out.tried.length} 条线路并同步最新订阅，仍无法访问外网，请稍后重试或刷新线路',
          );
          break;
      }
    } catch (e) {
      if (_cancelRequested) {
        _setPhase(ConnPhase.idle, '已取消连接');
        return;
      }
      final notice = SubscriptionService.lastNotice.value;
      if (notice != null) {
        _setPhase(ConnPhase.error, notice);
      } else if (!(await _probeLocal()).ok) {
        _setPhase(ConnPhase.offline, '当前网络不可用，请检查 Wi-Fi 或移动数据后重试');
      } else {
        _setPhase(ConnPhase.error, _friendlyConnectError(e));
      }
    } finally {
      _supervising = false;
      _supervisor = null;
    }
  }

  static String _friendlyConnectError(Object e) {
    final s = e.toString().replaceAll('Exception: ', '');
    if (s.contains('获取线路超时')) return '获取线路超时，请检查网络后重试';
    if (s.contains('403') || s.contains('登录')) return '登录已失效，请在「我的」页重新登录';
    if (s.contains('Failed to fetch nodes') || s.contains('subscription')) {
      return '暂时无法获取线路，请稍后重试';
    }
    return '连接出错，请稍后重试或切换线路';
  }

  /// 隧道已在运行（App 重开 / 外部拉起）：验证一次出网，通过则进入已连接并开启健康检查
  Future<void> _verifyExistingTunnel() async {
    if (_supervising || _isConnecting) return;
    _setPhase(ConnPhase.verifying, '正在验证网络…');
    var r = await _probeEgress();
    if (!r.ok) {
      await Future.delayed(const Duration(milliseconds: 1500));
      r = await _probeEgress();
    }
    if (!mounted || _supervising || _isConnecting) return;
    if (r.ok) {
      _setPhase(ConnPhase.connected,
          _activeName != null ? '已连接 $_activeName' : '已连接');
      _health.start();
      _restoreActiveNode();
      return;
    }
    final local = await _probeLocal();
    if (!local.ok) {
      _setPhase(ConnPhase.degraded, '手机网络不可用，网络恢复后自动继续');
      _health.start(firstDelay: const Duration(seconds: 20));
      return;
    }
    await _autoFailover();
  }

  void _onHealthVerdict(HealthVerdict v) {
    if (!mounted || _supervising || _isConnecting) return;
    switch (v) {
      case HealthVerdict.healthy:
        if (_phase == ConnPhase.degraded) {
          _setPhase(ConnPhase.connected,
              _activeName != null ? '已连接 $_activeName' : '已连接');
        }
        break;
      case HealthVerdict.offline:
        // 本机断网不是线路问题：不切换，等网络恢复
        _setPhase(ConnPhase.degraded, '手机网络不可用，网络恢复后自动继续');
        break;
      case HealthVerdict.unhealthy:
        _autoFailover();
        break;
      case HealthVerdict.skipped:
        break;
    }
  }

  /// 连接中途线路失效：按预算（10 分钟最多 3 次，间隔 ≥60 秒）自动切换，防止来回抖动
  Future<void> _autoFailover() async {
    if (_isConnecting || _supervising) return;
    if (!_failoverBudget.tryUse()) {
      _setPhase(ConnPhase.degraded, '线路不稳定，已多次自动切换，建议手动换一条线路');
      if (!_health.running) _health.start();
      return;
    }
    _isConnecting = true;
    try {
      await _runConnect(
        exclude: {if (_activeName != null) _activeName!},
        switching: true,
        newSession: false,
      );
    } finally {
      _isConnecting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _disconnect() async {
    _health.stop();
    _liveLatencyMs = null;
    _warmPending = false;
    _failoverBudget.reset();
    // v1.5.8：断开即落盘每日/线路用量
    DailyUsageService.instance.stop();
    // v1.5.8：记录切换历史
    _logSwitch('off', '已断开连接');
    _setPhase(ConnPhase.disconnecting, '正在断开…');
    await _vpnService.disconnect();
    _setPhase(ConnPhase.idle, '已断开');
  }

  /// 用户在连接中途取消（点光球 / 托盘断开）
  bool _cancelRequested = false;

  Future<void> _cancelConnecting() async {
    if (_cancelRequested) return;
    _cancelRequested = true;
    _supervisor?.cancel();
    _health.stop();
    _setPhase(ConnPhase.disconnecting, '正在取消连接…');
    try {
      await _vpnService.disconnect();
    } catch (_) {}
  }

  Future<void> _toggleConnection() async {
    if (_isConnecting) {
      // 连接 / 验证 / 切换中再次点击 = 取消（以前这里直接忽略，用户只能干等）
      if (_phase == ConnPhase.connecting ||
          _phase == ConnPhase.verifying ||
          _phase == ConnPhase.switching) {
        await _cancelConnecting();
      }
      return;
    }

    _isConnecting = true;
    try {
      if (_phase.online || _phase == ConnPhase.verifying) {
        await _disconnect();
      } else {
        _failoverBudget.reset();
        await _runConnect();
      }
    } catch (e) {
      _setPhase(ConnPhase.error, '连接出错：$e');
    } finally {
      _isConnecting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _reconnectConnection() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      _health.stop();
      _setPhase(ConnPhase.connecting, '正在连接…');
      try {
        await _vpnService.disconnect();
      } catch (_) {}
      _failoverBudget.reset();
      await _runConnect(newSession: false);
    } catch (e) {
      _setPhase(ConnPhase.error, '连接出错：$e');
    } finally {
      _isConnecting = false;
      if (mounted) setState(() {});
    }
  }

  /// 全部线路不可用时：手动刷新订阅（2 分钟防抖）后重新连接
  Future<void> _refreshAndRetry() async {
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      _setPhase(ConnPhase.connecting, '正在同步最新线路…');
      try {
        await _subscriptionService
            .fetchNodes(forceRefresh: true)
            .timeout(const Duration(seconds: 15));
      } catch (_) {}
      _failoverBudget.reset();
      await _runConnect();
    } finally {
      _isConnecting = false;
      if (mounted) setState(() {});
    }
  }

  /// 全部线路并发测速（有新鲜缓存时立即返回并后台复测），按延迟从低到高排序；不可达节点排在最后。
  /// 自动选择 / 自动切换都基于全部线路，而不是列表里按地区展示的那几条。
  /// v1.5.15：按「视频优先」开关选择排序口径。
  Future<List<ServerNode>> _rankNodesByLatency(List<ServerNode> nodes) =>
      LatencyTestService().rankFast(nodes, videoFirst: _videoFirst);

  /// v1.5.15：切换「视频优先」。持久化后若当前处于自动模式且已连接，
  /// 立即按新口径重新选线一次（复用既有重连入口，不新造连接逻辑）。
  Future<void> _setVideoFirst(bool value) async {
    if (_videoFirst == value) return;
    setState(() => _videoFirst = value);
    await LatencyTestService.writeVideoFirst(value);
    if (_autoMode && _phase.online) {
      unawaited(_reconnectConnection());
    }
  }

  /// App 被杀后重新打开、隧道仍在：按名称找回当前线路，补上协议 / 延迟展示
  Future<void> _restoreActiveNode() async {
    final name = _activeName;
    if (name == null || _activeNode != null) return;
    try {
      final nodes = await _subscriptionService.fetchNodes(preferCache: true);
      final n = nodes.cast<ServerNode?>().firstWhere(
          (x) => NodeLabel.same(x!.name, name),
          orElse: () => null);
      if (n == null || !mounted) return;
      setState(() => _activeNode = n);
      _measureActive(n);
    } catch (_) {}
  }

  /// 连接后补测一次当前线路延迟，用于首页展示
  Future<void> _measureActive(ServerNode node) async {
    if (node.latency != null) return;
    final v = await LatencyTestService()
        .testLatency(node, timeout: const Duration(seconds: 3));
    if (!mounted || v == null) return;
    setState(() => node.latency = v);
  }

  /// 手动选择线路：记住选择 → 连接（失败先重试该线路 2 次，再回落到最快的其他线路并提示）
  Future<void> _connectNode(ServerNode node) async {
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_node_name', node.name);
      await prefs.setBool('node_manual_selected', true);
      _autoMode = false;
      _health.stop();
      try {
        await _vpnService.disconnect();
      } catch (_) {}
      _failoverBudget.reset();
      await _runConnect();
    } catch (e) {
      _setPhase(ConnPhase.error, '连接出错：$e');
    } finally {
      _isConnecting = false;
      if (mounted) setState(() {});
    }
  }

  /// 切回「自动选择」：清除手动选择并按最快线路重新连接
  Future<void> _selectAuto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('node_manual_selected', false);
    if (mounted) setState(() => _autoMode = true);
    await _reconnectConnection();
  }

  /// v1.5.8：连接状态与切换历史弹层
  void _showSwitchHistory() {
    final phaseNow = _phase;
    final statusNow = _statusMessage;
    final active = _activeName;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 大状态图
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _SwitchIcon.kindColor(
                                  phaseNow.online
                                      ? 'ok'
                                      : phaseNow.failed
                                          ? 'fail'
                                          : phaseNow.busy
                                              ? 'busy'
                                              : 'idle')
                              .withValues(alpha: .14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _SwitchIcon.kindIcon(phaseNow.online
                          ? 'ok'
                          : phaseNow.failed
                              ? 'fail'
                              : phaseNow.busy
                                  ? 'busy'
                                  : 'idle'),
                      size: 22,
                      color: _SwitchIcon.kindColor(phaseNow.online
                          ? 'ok'
                          : phaseNow.failed
                              ? 'fail'
                              : phaseNow.busy
                                  ? 'busy'
                                  : 'idle'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('连接状态',
                            style: DzText.caption
                                .copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text(
                          active != null
                              ? statusNow.isNotEmpty
                                  ? statusNow
                                  : '已连接 ${NodeLabel.stableKey(active)}'
                              : statusNow.isNotEmpty
                                  ? statusNow
                                  : '未连接',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DzText.title.copyWith(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text('切换记录',
                  style:
                      DzText.caption.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              if (_switchHistory.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('暂无记录，连接后自动记录切换情况',
                      style: DzText.caption
                          .copyWith(color: AppColors.textTertiary)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _switchHistory.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) =>
                        _SwitchHistoryRow(record: _switchHistory[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showNodePicker() async {
    if (_isConnecting) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      isDismissible: true,
      elevation: 0,
      builder: (_) => NodePickerSheet(
        currentName: _activeName,
        autoMode: _autoMode,
        videoFirst: _videoFirst,
        onNodeSelected: _connectNode,
        onAutoSelected: _selectAuto,
        onVideoFirstChanged: _setVideoFirst,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: _BootLoader(),
      );
    }
    return _buildMainScaffold();
  }

  /// 创建指定索引的页面 (每次都返回新实例以获取最新 props)
  Widget _buildPage(int index) {
    switch (index) {
      case 0: // Home
        final busy = _phase.busy;
        return HomeDashboard(
          onConnectPressed: _toggleConnection,
          onReconnectRequested: _reconnectConnection,
          onOpenNodes: _showNodePicker,
          onOpenHistory: _showSwitchHistory,
          isConnected: _phase.online,
          isConnecting: busy,
          isError: _phase.failed,
          phase: _phase,
          onRefreshAndRetry: _refreshAndRetry,
          statusMessage: _statusMessage,
          nodeName: _activeName,
          nodeLatency: _activeNode?.latency,
          liveLatency: _liveLatencyMs,
          nodeBandwidth: _activeNode?.bandwidthMbps,
          nodeProtocol: _activeNode?.protocol,
          autoMode: _autoMode,
          videoFirst: _videoFirst,
          onVideoFirstChanged: _setVideoFirst,
        );
      case 1: // Account
        return AccountScreen(
          onLogout: _logoutCleanup,
          connectionStatus: _statusMessage,
          connectionState: _phase.online ? 'connected' : _phase.name,
          reloadToken: _accountReload,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// 两个页面常驻（保留状态），切换时只对「内容」交叉淡入 + 轻微位移。
  /// 背景由全局外壳（main.dart dzAppBuilder）绘制在这一层之外，所以切换时背景完全静止；
  /// 页面内不再含 BackdropFilter（它在透明度动画层里会采样到空白层而闪黑）。
  Widget _buildPages() {
    const dur = Duration(milliseconds: 320);
    return Stack(
      children: List.generate(2, (i) {
        final sel = i == _index;
        final child = _visitedIndices.contains(i) ? _buildPage(i) : const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            ignoring: !sel,
            child: ExcludeSemantics(
              excluding: !sel,
              child: AnimatedOpacity(
                duration: dur,
                curve: sel ? DzMotion.ease : Curves.easeIn,
                opacity: sel ? 1 : 0,
                child: AnimatedSlide(
                  duration: dur,
                  curve: DzMotion.emphasized,
                  offset: sel ? Offset.zero : Offset(i < _index ? -0.03 : 0.03, 0),
                  child: RepaintBoundary(
                    child: TickerMode(enabled: sel, child: child),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildMainScaffold() {
    // 桌面端使用侧边导航
    if (_isDesktop) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Row(
          children: [
            DesktopNav(
              selectedIndex: _index == 0 ? 0 : 2,
              onDestinationSelected: (i) => _switchTab(i == 0 ? 0 : 1),
            ),
            Expanded(child: _buildPages()),
          ],
        ),
      );
    }

    // 移动端：沉浸式背景 + 悬浮玻璃导航
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPages()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GlassNavBar(
              selectedIndex: _index,
              onDestinationSelected: _switchTab,
            ),
          ),
        ],
      ),
    );
  }
}

/// v1.5.8：连接/切换历史记录
class _SwitchRecord {
  final DateTime time;
  final String kind; // ok | auto | fail | off | busy | idle
  final String text;
  _SwitchRecord(this.time, this.kind, this.text);
}

/// v1.5.8：记录类型 → 图标/颜色
class _SwitchIcon {
  static IconData kindIcon(String kind) => switch (kind) {
        'ok' => Icons.check_rounded,
        'auto' => Icons.sync_rounded,
        'fail' => Icons.warning_amber_rounded,
        'off' => Icons.power_settings_new_rounded,
        'busy' => Icons.sync_rounded,
        _ => Icons.circle_outlined,
      };

  static Color kindColor(String kind) => switch (kind) {
        'ok' => AppColors.success,
        'auto' => AppColors.gold,
        'fail' => AppColors.danger,
        'off' => AppColors.textSecondary,
        'busy' => AppColors.gold,
        _ => AppColors.textTertiary,
      };
}

/// v1.5.8：切换历史时间线行
class _SwitchHistoryRow extends StatelessWidget {
  final _SwitchRecord record;
  const _SwitchHistoryRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final hh = record.time.hour.toString().padLeft(2, '0');
    final mm = record.time.minute.toString().padLeft(2, '0');
    final ss = record.time.second.toString().padLeft(2, '0');
    final color = _SwitchIcon.kindColor(record.kind);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 时间列
        SizedBox(
          width: 52,
          child: Text('$hh:$mm:$ss',
              style: DzText.caption.copyWith(
                  fontSize: 11, color: AppColors.textTertiary)),
        ),
        // 节点圆点 + 竖线
        Column(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Container(width: 1, height: 26, color: AppColors.borderStrong),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(record.kind == 'off'
                    ? Icons.power_settings_new_rounded
                    : record.kind == 'fail'
                        ? Icons.warning_amber_rounded
                        : record.kind == 'auto'
                            ? Icons.sync_rounded
                            : Icons.check_rounded,
                    size: 13,
                    color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(record.text,
                      style: DzText.caption
                          .copyWith(color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BootLoader extends StatelessWidget {
  const _BootLoader();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(height: 64),
          SizedBox(height: 28),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.gold,
              backgroundColor: Color(0x1AFFFFFF),
            ),
          ),
          SizedBox(height: 14),
          Text('正在为你优选线路…', style: DzText.caption),
        ],
      ),
    );
  }
}
