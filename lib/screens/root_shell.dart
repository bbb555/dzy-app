import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../services/latency_test_service.dart';
import '../services/subscription_service.dart';

import '../services/unified_vpn_service.dart';
import '../services/tray_service.dart';
import '../services/remote_config_service.dart';
import '../services/update_service.dart';
import '../services/user_data_service.dart';
import '../models/server_node.dart';
import '../theme/app_colors.dart';
import 'account_screen.dart';
import 'home_dashboard.dart';
import '../widgets/dz_ui.dart';
import '../widgets/glass_nav_bar.dart';
import '../widgets/desktop_nav.dart';
import '../widgets/node_picker_sheet.dart';
import '../widgets/update_dialog.dart';

import 'package:window_manager/window_manager.dart';

enum ShellStatus { disconnected, connecting, connected, error }

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

  ShellStatus _status = ShellStatus.disconnected;
  String _statusMessage = '';
  int _index = 0;
  final int _accountReload = 0;
  bool _isConnecting = false;
  bool _isInitializing = true; // 全局初始化状态

  // 当前线路展示
  ServerNode? _activeNode;
  String? _activeName;
  bool _autoMode = true;

  // 订阅定时刷新：前台或已连接时每 10 分钟检查一次，缓存超过 1 小时才真正请求服务器
  Timer? _subTimer;
  bool _foreground = true;

  // Lazy loading: 跟踪哪些页面已经被访问
  final Set<int> _visitedIndices = {0}; // 默认加载首页

  // 判断是否是桌面平台
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _vpnService.statusStream.listen(_onVpnStatusChanged);
    WidgetsBinding.instance.addObserver(this);

    // 统一初始化流程
    _initApp();

    // 初始化窗口监听
    if (_isDesktop) {
      windowManager.addListener(this);
      _initWindow();
    }
  }

  /// 统一初始化所有关键数据
  Future<void> _initApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoMode = !(prefs.getBool('node_manual_selected') ?? false);
      _activeName = prefs.getString('last_node_name');

      // 1. 基础服务 (Tray)
      await _initTray();

      // 2. 检查 VPN 状态
      await _checkInitialStatus();

      // 3. 核心网络配置 (获取并缓存最快域名)
      await RemoteConfigService().getActiveDomain();

      // 4. 仅加载 Home 页需要的数据（公告、节点）
      // 订阅缓存超过 1 小时会在这里自动从服务器刷新（失败回退缓存，最多等 8 秒）
      await Future.wait([
        UserDataService().getNotices(),
        _subscriptionService.fetchNodes(),
      ]);
    } catch (e) {
      debugPrint('Initialization failed: $e');
    }
    // 即使部分失败，也允许进入主页
    if (mounted) setState(() => _isInitializing = false);
    _syncSubscriptionTimer();
    // 启动后稍等再检查更新（最多每 6 小时一次），不打扰首屏
    Future.delayed(const Duration(seconds: 4), () => _autoCheckUpdate());
  }

  // ── 订阅自动刷新 ─────────────────────────────────────
  bool get _shouldTickSubscription =>
      _foreground || _status == ShellStatus.connected;

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
    _subTimer?.cancel();
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
          if (_status == ShellStatus.connected ||
              _status == ShellStatus.connecting) {
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
      setState(() {
        _status = ShellStatus.connected;
        _statusMessage = '已连接';
      });
    }
  }

  void _onVpnStatusChanged(bool isConnected) {
    if (!mounted) return;
    // 只处理从连接变为断开的情况（VPN 被后台杀死）
    if (!isConnected && _status == ShellStatus.connected) {
      setState(() {
        _status = ShellStatus.disconnected;
        _statusMessage = '已断开';
      });
    } else if (isConnected && _status != ShellStatus.connected) {
      setState(() {
        _status = ShellStatus.connected;
        _statusMessage = '已连接';
      });
    }
    _syncSubscriptionTimer();
  }

  void _switchTab(int newIndex) {
    if (newIndex == _index) return;
    setState(() {
      _index = newIndex;
      _visitedIndices.add(newIndex);
    });
  }

  void _setStatus(ShellStatus st, String msg) {
    if (!mounted) return;
    setState(() {
      _status = st;
      _statusMessage = msg;
    });
    _syncSubscriptionTimer();
  }

  Future<void> _toggleConnection() async {
    if (_isConnecting) return;

    _isConnecting = true;
    try {
      if (_status == ShellStatus.connected) {
        _setStatus(ShellStatus.connecting,
            '正在断开…');
        await _vpnService.disconnect();
        _setStatus(ShellStatus.disconnected,
            '已断开');
      } else {
        await _connectWithLastNode();
      }
    } catch (e) {
      _setStatus(ShellStatus.error, '连接出错：$e');
    } finally {
      _isConnecting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _reconnectConnection() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      _setStatus(ShellStatus.connecting,
          '正在连接…');
      try {
        await _vpnService.disconnect();
      } catch (_) {}

      await _connectWithLastNode();
    } catch (e) {
      _setStatus(ShellStatus.error, '连接出错：$e');
    } finally {
      _isConnecting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _connectWithLastNode() async {
    _setStatus(ShellStatus.connecting,
        '正在获取线路…');

    try {
      // 获取节点列表
      final nodes = await _subscriptionService.fetchNodes().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('获取线路超时，请检查网络'),
      );

      if (nodes.isEmpty) {
        _setStatus(ShellStatus.error, '暂无可用线路，请确认订阅是否有效');
        return;
      }

      // 读取上次手动选择的节点
      final prefs = await SharedPreferences.getInstance();
      final lastNodeName = prefs.getString('last_node_name');
      // 默认“自动选择”：未手动选过节点时，测速后按延迟从低到高依次尝试
      final manualSelected = prefs.getBool('node_manual_selected') ?? false;
      _autoMode = !manualSelected;

      List<ServerNode> candidates;
      if (manualSelected && lastNodeName != null) {
        final idx = nodes.indexWhere((n) => n.name == lastNodeName);
        candidates = idx >= 0 ? [nodes[idx]] : await _rankNodesByLatency(nodes);
      } else {
        _setStatus(ShellStatus.connecting, '全节点并发测速，锁定最快线路…');
        candidates = await _rankNodesByLatency(nodes);
      }

      ServerNode targetNode = candidates.first;
      bool success = false;
      Future<void> tryCandidates(Iterable<ServerNode> list) async {
        for (final node in list) {
          targetNode = node;
          _setStatus(ShellStatus.connecting, '正在连接 ${node.name}');
          success = await _vpnService
              .connect(node)
              .timeout(const Duration(seconds: 30), onTimeout: () => false);
          if (success) break;
          try {
            await _vpnService.disconnect();
          } catch (_) {}
        }
      }

      await tryCandidates(candidates.take(3));

      // 全部候选失败：线路可能已被官网下架 / 重排 → 立即刷新订阅（10 分钟防抖），再重试一轮
      if (!success) {
        _setStatus(ShellStatus.connecting, '正在同步最新线路…');
        final fresh = await _subscriptionService.refreshAfterConnectFailure();
        if (fresh != null && fresh.isNotEmpty) {
          List<ServerNode> retry;
          final mi = (manualSelected && lastNodeName != null)
              ? fresh.indexWhere((n) => n.name == lastNodeName)
              : -1;
          if (mi >= 0) {
            retry = [fresh[mi]];
          } else {
            _setStatus(ShellStatus.connecting, '全节点并发测速，锁定最快线路…');
            retry = await _rankNodesByLatency(fresh);
          }
          await tryCandidates(retry.take(2));
        }
      }

      if (success) {
        await prefs.setString('last_node_name', targetNode.name);
        _activeNode = targetNode;
        _activeName = targetNode.name;
        _measureActive(targetNode);
      }

      _setStatus(
        success ? ShellStatus.connected : ShellStatus.error,
        success ? '已连接 ${targetNode.name}' : '连接失败，请切换线路或稍后重试',
      );
    } catch (e) {
      _setStatus(ShellStatus.error,
          '连接出错：${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  /// 并发 TCP 测速，按延迟从低到高排序；不可达节点排在最后
  Future<List<ServerNode>> _rankNodesByLatency(List<ServerNode> nodes) async {
    final tester = LatencyTestService();
    try {
      await Future.wait(nodes.map((n) async {
        n.latency = await tester.testLatency(n,
            timeout: const Duration(seconds: 3));
      })).timeout(const Duration(seconds: 6));
    } catch (_) {}
    final ranked = List<ServerNode>.from(nodes);
    ranked.sort((a, b) =>
        (a.latency ?? 999999).compareTo(b.latency ?? 999999));
    return ranked;
  }

  /// 连接后补测一次当前线路延迟，用于首页展示
  Future<void> _measureActive(ServerNode node) async {
    if (node.latency != null) return;
    final v = await LatencyTestService()
        .testLatency(node, timeout: const Duration(seconds: 3));
    if (!mounted || v == null) return;
    setState(() => node.latency = v);
  }

  Future<void> _connectNode(ServerNode node) async {
    if (_isConnecting) return;
    _isConnecting = true;
    _setStatus(ShellStatus.connecting, '正在连接 ${node.name}');
    try {
      await _vpnService.disconnect();
      final success = await _vpnService.connect(node);

      // 保存手动选择的节点
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_node_name', node.name);
        await prefs.setBool('node_manual_selected', true);
        _autoMode = false;
        _activeNode = node;
        _activeName = node.name;
        _measureActive(node);
      }

      if (!success) {
        // 手动线路连接失败：后台同步一次订阅（10 分钟防抖），线路列表下次打开即为最新
        _subscriptionService.refreshAfterConnectFailure();
      }

      _setStatus(
        success ? ShellStatus.connected : ShellStatus.error,
        success ? '已连接 ${node.name}' : '连接失败，请切换线路或稍后重试',
      );
    } catch (e) {
      _setStatus(ShellStatus.error, '连接出错：$e');
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
        onNodeSelected: _connectNode,
        onAutoSelected: _selectAuto,
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
        final busy = _isConnecting || _status == ShellStatus.connecting;
        return HomeDashboard(
          onConnectPressed: _toggleConnection,
          onReconnectRequested: _reconnectConnection,
          onOpenNodes: _showNodePicker,
          isConnected: _status == ShellStatus.connected,
          isConnecting: busy,
          isError: _status == ShellStatus.error,
          statusMessage: _statusMessage,
          nodeName: _activeName,
          nodeLatency: _activeNode?.latency,
          nodeProtocol: _activeNode?.protocol,
          autoMode: _autoMode,
        );
      case 1: // Account
        return AccountScreen(
          onLogout: widget.onLogout,
          connectionStatus: _statusMessage,
          connectionState: _status.name,
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
