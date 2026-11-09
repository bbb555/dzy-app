import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/plan.dart';
import '../services/latency_test_service.dart';
import '../services/subscription_service.dart';

import '../services/unified_vpn_service.dart';
import '../services/tray_service.dart';
import '../services/remote_config_service.dart'; // Added
import '../services/user_data_service.dart'; // Added
import '../models/server_node.dart';
import '../theme/app_colors.dart';
import 'account_screen.dart';
import 'home_dashboard.dart';
import 'plans_screen.dart';
import 'orders_screen.dart';
import '../widgets/animated_background.dart';
import '../widgets/flux_loader.dart';
import '../widgets/glass_nav_bar.dart';
import '../widgets/desktop_nav.dart';
import '../widgets/node_picker_sheet.dart';

import 'package:window_manager/window_manager.dart';

enum ShellStatus { disconnected, connecting, connected, error }

class RootShell extends StatefulWidget {
  final VoidCallback onLogout;
  const RootShell({super.key, required this.onLogout});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WindowListener {
  final _subscriptionService = SubscriptionService();
  final _vpnService = UnifiedVpnService.instance;
  final _trayService = TrayService.instance;

  ShellStatus _status = ShellStatus.disconnected;
  String _statusMessage = '';
  int _index = 0;
  bool _isSwitching = false;
  int _accountReload = 0;
  bool _isConnecting = false;
  List<ServerNode>? _nodesCache;
  bool _isInitializing = true; // 全局初始化状态

  // Lazy loading: 跟踪哪些页面已经被访问
  final Set<int> _visitedIndices = {0}; // 默认加载首页

  // 判断是否是桌面平台
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _vpnService.statusStream.listen(_onVpnStatusChanged);

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
      // 1. 基础服务 (Tray)
      await _initTray();

      // 2. 检查 VPN 状态
      await _checkInitialStatus();

      // 3. 核心网络配置 (获取并缓存最快域名)
      await RemoteConfigService().getActiveDomain();

      // 4. ✅ 仅加载 Home 页需要的数据（公告）
      // 其他页面数据将在用户切换到对应 tab 时才加载
      await Future.wait([
        UserDataService().getNotices(), // Home 页公告
        _subscriptionService.fetchNodes(), // 节点列表（VPN 功能需要）
      ]);

      // 5. 初始化完成
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      debugPrint('Initialization failed: $e');
      // 即使部分失败，也允许进入主页
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _initWindow() async {
    await windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
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
        _statusMessage = AppLocalizations.of(context)?.connected ?? '已连接';
      });
    }
  }

  void _onVpnStatusChanged(bool isConnected) {
    if (!mounted) return;
    // 只处理从连接变为断开的情况（VPN 被后台杀死）
    if (!isConnected && _status == ShellStatus.connected) {
      setState(() {
        _status = ShellStatus.disconnected;
        _statusMessage = AppLocalizations.of(context)?.disconnected ?? '已断开';
      });
    } else if (isConnected && _status != ShellStatus.connected) {
      setState(() {
        _status = ShellStatus.connected;
        _statusMessage = AppLocalizations.of(context)?.connected ?? '已连接';
      });
    }
  }

  Future<void> _openCheckout(Plan plan) async {
    await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => OrdersScreen(
          selectedPlan: plan,
          onPickPlan: () => Navigator.of(context).pop(),
          onPaid: _handlePaid,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );

    // 无论如何返回后都刷新订阅信息（可能支付成功但用户用返回键关闭）
    if (mounted) {
      setState(() {
        _accountReload++;
      });
    }
  }

  void _handlePaid() {
    setState(() {
      _accountReload++;
      _index = 0;
    });
  }

  Future<void> _switchTab(int newIndex) async {
    if (newIndex == _index) return;

    setState(() {
      _isSwitching = true;
    });

    await Future.delayed(const Duration(milliseconds: 50));

    setState(() {
      _index = newIndex;
      _isSwitching = false;
      // Lazy loading: 标记此页面已被访问
      _visitedIndices.add(newIndex);
    });
  }

  Future<void> _toggleConnection() async {
    // ??????????????????
    if (_isConnecting) return;

    _isConnecting = true;
    try {
      if (_status == ShellStatus.connected) {
        setState(() {
          _status = ShellStatus.connecting;
          _statusMessage =
              AppLocalizations.of(context)?.disconnecting ?? '????????????...';
        });
        await _vpnService.disconnect();
        setState(() {
          _status = ShellStatus.disconnected;
          _statusMessage =
              AppLocalizations.of(context)?.disconnected ?? '?????????';
        });
      } else {
        await _connectWithLastNode();
      }
    } catch (e) {
      setState(() {
        _status = ShellStatus.error;
        _statusMessage = '${AppLocalizations.of(context)?.error ?? "??????"}: $e';
      });
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _reconnectConnection() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      setState(() {
        _status = ShellStatus.connecting;
        _statusMessage =
            AppLocalizations.of(context)?.connecting ?? '????????????...';
      });

      if (_status == ShellStatus.connected || _status == ShellStatus.connecting) {
        try {
          await _vpnService.disconnect();
        } catch (_) {}
      }

      await _connectWithLastNode();
    } catch (e) {
      setState(() {
        _status = ShellStatus.error;
        _statusMessage = '${AppLocalizations.of(context)?.error ?? "??????"}: $e';
      });
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _connectWithLastNode() async {
    setState(() {
      _status = ShellStatus.connecting;
      _statusMessage =
          AppLocalizations.of(context)?.loadingConfig ?? '??????????????????...';
    });

    try {
      // ??????????????????
      final nodes = await _subscriptionService.fetchNodes().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception(
          AppLocalizations.of(context)?.fetchNodesTimeout ?? '??????????????????',
        ),
      );

      if (nodes.isEmpty) {
        setState(() {
          _status = ShellStatus.error;
          _statusMessage =
              AppLocalizations.of(context)?.noNodes ?? '??????????????????';
        });
        return;
      }

      // ???????????????????????????
      final prefs = await SharedPreferences.getInstance();
      final lastNodeName = prefs.getString('last_node_name');
      // 默认“自动选择”：未手动选过节点时，测速后按延迟从低到高依次尝试
      final manualSelected = prefs.getBool('node_manual_selected') ?? false;

      List<ServerNode> candidates;
      if (manualSelected && lastNodeName != null) {
        final idx = nodes.indexWhere((n) => n.name == lastNodeName);
        candidates = idx >= 0 ? [nodes[idx]] : await _rankNodesByLatency(nodes);
      } else {
        setState(() {
          _statusMessage = '自动选择最快线路...';
        });
        candidates = await _rankNodesByLatency(nodes);
      }

      ServerNode targetNode = candidates.first;
      bool success = false;
      for (final node in candidates.take(3)) {
        targetNode = node;
        setState(() {
          _statusMessage =
              '${AppLocalizations.of(context)?.connecting ?? "正在连接"} ${node.name}...';
        });
        success = await _vpnService
            .connect(node)
            .timeout(const Duration(seconds: 30), onTimeout: () => false);
        if (success) break;
        try {
          await _vpnService.disconnect();
        } catch (_) {}
      }

      if (success) {
        await prefs.setString('last_node_name', targetNode.name);
      }

      setState(() {
        _status = success ? ShellStatus.connected : ShellStatus.error;
        _statusMessage = success
            ? '${AppLocalizations.of(context)?.connected ?? "?????????"} ${targetNode.name}'
            : AppLocalizations.of(context)?.connectionFailed ?? '????????????';
      });
    } catch (e) {
      setState(() {
        _status = ShellStatus.error;
        _statusMessage =
            '${AppLocalizations.of(context)?.error ?? "??????"}: ${e.toString().replaceAll('Exception: ', '')}';
      });
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

  Future<void> _connectNode(ServerNode node) async {
    if (_isConnecting) return;
    _isConnecting = true;
    setState(() {
      _status = ShellStatus.connecting;
      _statusMessage =
          '${AppLocalizations.of(context)?.connecting ?? "正在连接"} ${node.name}...';
    });
    try {
      await _vpnService.disconnect();
      final success = await _vpnService.connect(node);

      // 保存手动选择的节点
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_node_name', node.name);
        await prefs.setBool('node_manual_selected', true);
      }

      setState(() {
        _status = success ? ShellStatus.connected : ShellStatus.error;
        _statusMessage = success
            ? '${AppLocalizations.of(context)?.connected ?? "已连接"} ${node.name}'
            : AppLocalizations.of(context)?.connectionFailed ?? '连接失败';
      });
    } catch (e) {
      setState(() {
        _status = ShellStatus.error;
        _statusMessage = '${AppLocalizations.of(context)?.error ?? "错误"}: $e';
      });
    } finally {
      _isConnecting = false;
    }
  }

  bool _isLoadingNodes = false;

  Future<void> _showNodePicker() async {
    if (_isConnecting) return;

    // We don't need _isLoadingNodes anymore since NodePickerSheet handles it
    // But we keep the check to prevent opening while connecting

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Important for glass effect
      barrierColor: Colors.black54, // Ensure barrier is visible and interactive
      isDismissible: true,
      elevation: 0,
      // Allow dragging the sheet up to 90%
      builder: (_) => NodePickerSheet(
        onNodeSelected: (node) {
          // Connection logic
          _connectNode(node);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: FluxLoader()));
    }

    return _buildMainScaffold();
  }

  /// 创建指定索引的页面 (每次都返回新实例以获取最新 props)
  Widget _buildPage(int index) {
    switch (index) {
      case 0: // Home
        return HomeDashboard(
          onConnectPressed: _toggleConnection,
          onReconnectRequested: _reconnectConnection,
          isConnected: _status == ShellStatus.connected,
          isConnecting: _isConnecting || _status == ShellStatus.connecting,
          statusMessage: _statusMessage,
        );
      case 1: // Plans
        return PlansScreen(onChoose: _openCheckout);
      case 2: // Account
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

  /// 为 IndexedStack 构建延迟加载的 children
  List<Widget> _buildLazyPages() {
    return List.generate(3, (index) {
      // 只为已访问过的 tab 创建 widget
      if (_visitedIndices.contains(index)) {
        return _buildPage(index);
      }
      // 未访问的 tab 显示空 widget
      return const SizedBox.shrink();
    });
  }

  Widget _buildMainScaffold() {
    // 桌面端使用侧边导航
    if (_isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            // 侧边导航
            DesktopNav(
              selectedIndex: _index,
              onDestinationSelected: _switchTab,
            ),
            // 主内容区
            Expanded(
              child: Stack(
                children: [
                  // Global Background
                  const Positioned.fill(
                    child: AnimatedMeshBackground(child: SizedBox.expand()),
                  ),
                  // 顶部工具栏
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: _isLoadingNodes
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: FluxLoader(
                                      size: 20,
                                      color: AppColors.textPrimary,
                                    ),
                                  )
                                : const Icon(
                                    Icons.storage_rounded,
                                    color: AppColors.textPrimary,
                                  ),
                            tooltip:
                                AppLocalizations.of(context)?.nodeList ??
                                'Node List',
                            onPressed: _showNodePicker,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Content
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        opacity: _isSwitching ? 0.0 : 1.0,
                        child: IndexedStack(
                          index: _index,
                          children: _buildLazyPages(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 移动端使用底部导航
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.blur_on, color: AppColors.accent),
            const SizedBox(width: 8),
            const Text('队长云'),
            const Spacer(),
            IconButton(
              icon: _isLoadingNodes
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: FluxLoader(size: 20, color: AppColors.textPrimary),
                    )
                  : const Icon(
                      Icons.storage_rounded,
                      color: AppColors.textPrimary,
                    ),
              tooltip: AppLocalizations.of(context)?.nodeList ?? 'Node List',
              onPressed: _showNodePicker,
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          // Global Background
          const Positioned.fill(
            child: AnimatedMeshBackground(child: SizedBox.expand()),
          ),
          // Content
          Positioned.fill(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              opacity: _isSwitching ? 0.0 : 1.0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                offset: _isSwitching ? const Offset(0.01, 0.01) : Offset.zero,
                child: IndexedStack(index: _index, children: _buildLazyPages()),
              ),
            ),
          ),
          // Floating Nav Bar
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
