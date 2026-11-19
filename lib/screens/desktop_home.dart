import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notice.dart';
import '../models/server_node.dart';
import '../services/connection_supervisor.dart';
import '../services/latency_test_service.dart';
import '../services/subscription_service.dart';
import '../services/user_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/node_region.dart';
import '../utils/plan_quota.dart';
import '../widgets/desktop_home_kit.dart';

/// 电脑端（Windows）首页 —— 方案 A 光环连接盘 + 方案 B 极光玻璃。
///
/// 只在 Windows 端启用（见 [isDesktopUiSupported] + root_shell.dart 的平台分支），
/// 安卓端继续用 [HomeDashboard]，两边互不影响。
///
/// 布局对应设计稿 `desktop-ui-mock.html`：
/// · 顶部：品牌标题（渐变字）+ 公告条 + 会员 / 账号入口（右侧右上角）；
/// · 左侧：光环连接盘（点击连接 / 断开）+ 当前线路胶囊（点一下切线路）+ 主按钮 + 状态下拉；
/// · 右侧：线路卡片（点一下切线路）+「近 7 日加速时长」玻璃面板（柱图 + 指标）；
/// · 底部：状态条（内核 / 代理状态 + 版本 · 脱敏账号）。
class DesktopHome extends StatefulWidget {
  final VoidCallback onConnectPressed;
  final Future<void> Function()? onReconnectRequested;
  final VoidCallback? onOpenNodes;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenAccount;
  final ValueChanged<ServerNode>? onNodeSelected;
  final bool isConnected;
  final bool isConnecting;
  final bool isError;
  final String statusMessage;
  final String? nodeName;
  final int? nodeLatency;
  final int? liveLatency;
  final int? nodeBandwidth;
  final String? nodeProtocol;
  final bool autoMode;

  /// v1.3.0 细分连接阶段
  final ConnPhase? phase;

  /// 全部线路不可用时「刷新线路并重试」
  final Future<void> Function()? onRefreshAndRetry;

  /// 预览 / golden 测试注入（正常运行传 null = 走真实服务与本地统计）
  final DesktopPreview? preview;

  const DesktopHome({
    super.key,
    required this.onConnectPressed,
    this.onReconnectRequested,
    this.onOpenNodes,
    this.onOpenHistory,
    this.onOpenAccount,
    this.onNodeSelected,
    required this.isConnected,
    this.isConnecting = false,
    this.isError = false,
    this.statusMessage = '',
    this.nodeName,
    this.nodeLatency,
    this.liveLatency,
    this.nodeBandwidth,
    this.nodeProtocol,
    this.autoMode = true,
    this.phase,
    this.onRefreshAndRetry,
    this.preview,
  });

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

/// 电脑端首页是否启用：Windows 桌面端专用，安卓 / 其它平台不受影响
bool get isDesktopUiSupported {
  if (kIsWeb) return false;
  return Platform.isWindows;
}

/// 预览 / golden 注入数据（不联网、不读本地统计，保证 CI 里可重复渲染）
class DesktopPreview {
  final List<ServerNode> nodes;
  final List<int> weekSeconds;
  final String email;
  final int? daysLeft;
  final String? planName;
  final String? notice;
  final Duration session;

  const DesktopPreview({
    this.nodes = const [],
    this.weekSeconds = const [],
    this.email = '13800008888@qq.com',
    this.daysLeft,
    this.planName,
    this.notice,
    this.session = Duration.zero,
  });
}

/// 电脑端本地「每日加速时长」统计（Windows 内核没有流量计数器，只按时长统计）。
///
/// 只写 SharedPreferences 里自己的 key，不碰安卓的 [DailyUsageService] 数据。
class DeskSessionLog {
  static const String key = 'desk_accel_seconds_v1';
  final Map<String, int> _seconds = {};

  static String dayKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      j.forEach((k, v) {
        final n = v is num ? v.toInt() : int.tryParse(v.toString());
        if (n != null) _seconds[k.toString()] = n;
      });
    } catch (_) {/* 统计读不出来不影响首页 */}
  }

  int of(String key) => _seconds[key] ?? 0;

  void add(String key, int delta) => _seconds[key] = of(key) + delta;

  Future<void> flush() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 只保留最近 30 天，避免无限增长
      final keep = _seconds.keys.toList()..sort();
      while (keep.length > 30) {
        _seconds.remove(keep.removeAt(0));
      }
      await prefs.setString(key, jsonEncode(_seconds));
    } catch (_) {/* 忽略 */}
  }
}

class _DesktopHomeState extends State<DesktopHome> {
  static const String _appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  final DeskSessionLog _log = DeskSessionLog();
  Timer? _tick;
  Duration _session = Duration.zero;
  DateTime? _connectedAt;

  List<ServerNode> _nodes = const [];
  List<RegionGroup> _groups = const [];
  String _email = '';
  int _expiredAt = 0;
  String? _planName;
  String? _notice;

  bool get _previewMode => widget.preview != null;

  @override
  void initState() {
    super.initState();
    final p = widget.preview;
    if (p != null) {
      _email = p.email;
      _planName = p.planName;
      _notice = p.notice;
      _nodes = p.nodes;
      _groups = _group(p.nodes);
      _session = p.session;
      _seedPreviewWeek(p.weekSeconds);
      return;
    }
    _log.load();
    _loadNodes();
    _loadAccount();
    _loadNotice();
    _syncSessionTimer();
  }

  @override
  void didUpdateWidget(covariant DesktopHome old) {
    super.didUpdateWidget(old);
    if (!_previewMode) _syncSessionTimer();
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (!_previewMode) {
      _flushTick();
      _log.flush();
    }
    super.dispose();
  }

  bool get _online =>
      widget.isConnected || (widget.phase?.online ?? false);

  bool get _busy => widget.isConnecting || (widget.phase?.busy ?? false);

  bool get _failed => widget.isError || (widget.phase?.failed ?? false);

  int? get _latency => widget.liveLatency ?? widget.nodeLatency;

  // ── 计时：只有在线时才走秒表（同时累计今天的加速时长）
  void _syncSessionTimer() {
    if (_online) {
      _connectedAt ??= DateTime.now();
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    } else {
      _tick?.cancel();
      _tick = null;
      _connectedAt = null;
      if (!_previewMode) _flushTick();
      if (mounted && _session != Duration.zero) {
        setState(() => _session = Duration.zero);
      }
    }
  }

  int _flushedSeconds = 0;

  void _onTick() {
    final start = _connectedAt;
    if (start == null) return;
    _log.add(DeskSessionLog.dayKey(DateTime.now()), 1);
    _flushedSeconds++;
    if (_flushedSeconds >= 15) _flushTick();
    if (mounted) {
      setState(() => _session = DateTime.now().difference(start));
    }
  }

  void _flushTick() {
    if (_flushedSeconds == 0) return;
    _flushedSeconds = 0;
    _log.flush();
  }

  // ── 数据：节点 / 账号 / 公告
  List<RegionGroup> _group(List<ServerNode> nodes) {
    if (nodes.isEmpty) return const [];
    try {
      return NodeGrouping.group(nodes, perRegion: 1).take(3).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadNodes() async {
    try {
      final nodes = await SubscriptionService().fetchNodes(preferCache: true);
      await LatencyCache.instance.load();
      LatencyCache.instance.apply(nodes);
      if (!mounted) return;
      setState(() {
        _nodes = nodes;
        _groups = _group(nodes);
      });
    } catch (_) {
      if (mounted) setState(() => _groups = const []);
    }
  }

  Future<void> _loadAccount() async {
    try {
      final info = await UserDataService().getUserInfo();
      Map<String, dynamic> sub = const {};
      try {
        sub = await UserDataService().getSubscribeInfo();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _email = info.email;
        _expiredAt = info.expiredAt;
        _planName = PlanQuota.fromSubscribe(sub).planName;
      });
    } catch (_) {/* 未登录 / 离线：右上角退化成占位 */}
  }

  Future<void> _loadNotice() async {
    try {
      final list = await UserDataService().getNotices();
      if (!mounted || list.isEmpty) return;
      final n = Notice.fromJson(list.first);
      if (n.title.trim().isEmpty) return;
      setState(() => _notice = n.title.trim());
    } catch (_) {/* 没公告就不显示公告条 */}
  }

  // ── 近 7 日柱图
  List<Map<String, Object>> _week = const [];

  void _seedPreviewWeek(List<int> secs) {
    final now = DateTime.now();
    final out = <Map<String, Object>>[];
    for (var i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final idx = 6 - i;
      final v = idx < secs.length ? secs[idx] : 0;
      out.add({'label': '${d.month}/${d.day}', 'seconds': v});
    }
    _week = out;
  }

  List<Map<String, Object>> _weekData() {
    if (_previewMode) return _week;
    final now = DateTime.now();
    final live = _online ? DateTime.now() : null;
    final out = <Map<String, Object>>[];
    for (var i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      var v = _log.of(DeskSessionLog.dayKey(d));
      if (live != null && i == 0) v += _session.inSeconds;
      out.add({'label': '${d.month}/${d.day}', 'seconds': v});
    }
    return out;
  }

  List<DeskBar> _bars(List<Map<String, Object>> week) {
    var maxV = 1;
    for (final d in week) {
      final v = (d['seconds'] as int?) ?? 0;
      if (v > maxV) maxV = v;
    }
    return [
      for (final d in week)
        DeskBar(
          label: d['label'] as String,
          value: deskDuration(Duration(seconds: (d['seconds'] as int?) ?? 0)),
          fraction: ((d['seconds'] as int?) ?? 0) == 0
              ? 0.04
              : (((d['seconds'] as int?) ?? 0) / maxV).clamp(0.12, 1.0),
        ),
    ];
  }

  // ── 文案
  String get _haloTitle {
    if (_failed) return '连接异常';
    if (_busy) return '正在连接';
    if (_online) return '已连接';
    return '未连接';
  }

  String get _haloSubline {
    final s = widget.statusMessage.trim();
    if (s.isNotEmpty && (_online || _busy || _failed)) return s;
    if (_online) return '加速已生效';
    if (_busy) return '正在建立隧道…';
    if (_failed) return '线路异常，点击重试';
    return '点击开始加速';
  }

  String get _ctaLabel => _online ? '断开连接' : '一键连接';

  String? get _daysLeft {
    if (_expiredAt <= 0) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(_expiredAt * 1000)
        .difference(DateTime.now())
        .inDays;
    return d < 0 ? '已过期' : '剩 $d 天';
  }

  String get _expiryText {
    if (_expiredAt <= 0) return '未开通套餐';
    final t = DateTime.fromMillisecondsSinceEpoch(_expiredAt * 1000);
    return '有效期至 ${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  String get _planText {
    final name = (_planName ?? '').trim();
    final left = _daysLeft;
    final base = name.isEmpty ? '时长会员' : name;
    return left == null ? base : '$base · $left';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: AuroraBackground()),
        Positioned.fill(
          child: Column(
            children: [
              _topBar(),
              if (_notice != null && _notice!.isNotEmpty) _noticeBar(),
              Expanded(child: _body()),
              DeskStatusBar(
                left: _online
                    ? '内核运行中 · 系统代理已启用 · ${widget.nodeProtocol ?? 'auto'}'
                    : '内核就绪 · 系统代理未启用',
                right:
                    'v$_appVersion · ${_email.isEmpty ? '未登录' : deskMaskEmail(_email)}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 22, 34, 8),
      child: Row(
        children: [
          const DeskBrand(subtitle: '让世界快一步'),
          const Spacer(),
          PlanPill(
            text: _planText,
            sub: '今日 ${deskDuration(Duration(seconds: _weekData().last['seconds'] as int? ?? 0))}',
          ),
          const SizedBox(width: 16),
          _accountEntry(),
        ],
      ),
    );
  }

  Widget _accountEntry() {
    final initial = _email.isEmpty ? '客' : _email.substring(0, 1).toUpperCase();
    return DeskTap(
      onTap: widget.onOpenAccount,
      tooltip: '账号与套餐',
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: DzDesk.glassSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: DzDesk.glassSoftLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [DzDesk.blue, DzDesk.violet],
                ),
              ),
              child: Text(
                initial,
                style: DzDesk.f(const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                )),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _email.isEmpty ? '未登录' : deskMaskEmail(_email),
                  style: DzDesk.f(const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: DzDesk.textSoft,
                  )),
                ),
                Text(
                  _expiryText,
                  style: DzDesk.f(const TextStyle(
                    fontSize: 11,
                    color: DzDesk.textDim,
                  )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _noticeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 6, 34, 4),
      child: AnnouncementBar(text: _notice!),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 960;
        final left = _connectColumn();
        final right = _cardsColumn();
        if (!wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(
              children: [
                left,
                const SizedBox(height: 20),
                SizedBox(height: 560, child: right),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(34, 6, 34, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 26),
              Expanded(child: right),
            ],
          ),
        );
      },
    );
  }

  Widget _connectColumn() {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConnectHalo(
                    title: _haloTitle,
                    subline: _haloSubline,
                    online: _online,
                    busy: _busy,
                    failed: _failed,
                    onTap: widget.onConnectPressed,
                  ),
                  const SizedBox(height: 26),
                  RoutePillRow(
                    route: _routeText,
                    latency: _latency,
                    onTap: widget.onOpenNodes,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DeskCta(
                        label: _ctaLabel,
                        busy: _busy,
                        onTap: widget.onConnectPressed,
                      ),
                      const SizedBox(width: 14),
                      DeskCta(
                        label: '测速',
                        ghost: true,
                        onTap: widget.onOpenNodes,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _statusDropdown(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _routeText {
    final name = (widget.nodeName ?? '').trim();
    if (name.isEmpty) return '智能优选线路';
    return _autoModeSuffix(name);
  }

  String _autoModeSuffix(String name) =>
      widget.autoMode && !name.contains('智能') ? '$name · 智能优选' : name;

  Widget _statusDropdown() {
    return StatusDropdown(
      label: _statusLabel,
      detail: _online && _session.inSeconds > 0 ? deskClock(_session) : null,
      value: _online ? 'online' : (_failed ? 'failed' : 'idle'),
      actions: [
        const StatusAction('reconnect', '重新连接', Icons.refresh_rounded),
        const StatusAction('nodes', '选择线路', Icons.dns_rounded),
        const StatusAction('diag', '诊断与日志', Icons.receipt_long_rounded),
        if (widget.onRefreshAndRetry != null)
          const StatusAction('refresh', '刷新订阅并重试', Icons.cloud_sync_rounded),
      ],
      onSelected: (v) {
        switch (v) {
          case 'reconnect':
            final f = widget.onReconnectRequested;
            if (f != null) {
              f();
            } else {
              widget.onConnectPressed();
            }
            break;
          case 'nodes':
            widget.onOpenNodes?.call();
            break;
          case 'diag':
            widget.onOpenHistory?.call();
            break;
          case 'refresh':
            widget.onRefreshAndRetry?.call();
            break;
        }
      },
    );
  }

  String get _statusLabel {
    if (_failed) return '状态 · 连接异常';
    if (_busy) return '状态 · 连接中';
    if (_online) return '状态 · 已连接';
    return '状态 · 未连接';
  }

  Widget _cardsColumn() {
    final currentCode = widget.nodeName == null
        ? null
        : RegionParser.parse(widget.nodeName!).code;
    final week = _weekData();
    var totalSeconds = 0;
    for (final d in week) {
      totalSeconds += (d['seconds'] as int?) ?? 0;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '线路 · 点击切换',
              style: DzDesk.f(DzText.caption.copyWith(
                color: DzDesk.textMuted,
                letterSpacing: 0.6,
                fontSize: 12.5,
              )),
            ),
            const Spacer(),
            if (_nodes.isNotEmpty)
              Text(
                '共 ${_nodes.length} 条',
                style: DzDesk.f(const TextStyle(fontSize: 12, color: DzDesk.textDim)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_groups.isEmpty)
          GlassPanel(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 18, color: DzDesk.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '暂无线路，先刷新订阅',
                    style: DzDesk.f(
                        const TextStyle(fontSize: 13, color: DzDesk.textMuted)),
                  ),
                ),
                TextButton(
                  onPressed: widget.onRefreshAndRetry,
                  child: Text('刷新',
                      style: DzDesk.f(
                          const TextStyle(fontSize: 13, color: DzDesk.mint))),
                ),
              ],
            ),
          )
        else
          for (final g in _groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RouteCard(
                title: '${g.region.flag} ${g.region.name}',
                subtitle: g.bestLatency == null
                    ? '${g.all.length} 条线路 · 未测速'
                    : '${g.bestLatency}ms · ${g.all.length} 条线路',
                hot: currentCode != null && g.region.code == currentCode,
                badge: currentCode != null && g.region.code == currentCode
                    ? '当前'
                    : null,
                trailing: g.all.first.bandwidthMbps == null
                    ? null
                    : '${g.all.first.bandwidthMbps}M',
                onTap: widget.onNodeSelected == null
                    ? null
                    : () => widget.onNodeSelected!(g.top.first),
              ),
            ),
        const SizedBox(height: 4),
        Expanded(
          child: GlassPanel(
            radius: 22,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '近 7 日加速时长',
                      style: DzDesk.f(DzText.caption.copyWith(
                        color: DzDesk.textMuted,
                        fontSize: 12.5,
                        letterSpacing: 0.5,
                      )),
                    ),
                    const Spacer(),
                    Text(
                      '本机统计',
                      style: DzDesk.f(
                          const TextStyle(fontSize: 11, color: DzDesk.textDim)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(child: UsageBars(bars: _bars(week))),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  children: [
                    DeskMetric(
                      label: '今日',
                      value: deskDuration(Duration(
                          seconds: week.last['seconds'] as int? ?? 0)),
                    ),
                    DeskMetric(
                      label: '近 7 日累计',
                      value: deskDuration(Duration(seconds: totalSeconds)),
                    ),
                    DeskMetric(
                      label: '当前延迟',
                      value: _latency == null ? '--' : '$_latency ms',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
