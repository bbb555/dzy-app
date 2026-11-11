import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/server_node.dart';
import '../services/latency_test_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_colors.dart';
import '../utils/node_region.dart';
import 'dz_ui.dart';

/// 线路选择弹层：顶部「自动选择」+ 按地区分组的线路（每个地区默认展示最快 2 条，可展开全部；
/// 打开即并发测速，结果陆续到达时实时重排）
class NodePickerSheet extends StatefulWidget {
  final ValueChanged<ServerNode> onNodeSelected;
  final VoidCallback? onAutoSelected;
  final String? currentName;
  final bool autoMode;

  const NodePickerSheet({
    super.key,
    required this.onNodeSelected,
    this.onAutoSelected,
    this.currentName,
    this.autoMode = true,
    this.previewNodes,
  });

  /// 仅用于界面预览/测试：直接注入线路，不请求订阅、不测速
  @visibleForTesting
  final List<ServerNode>? previewNodes;

  /// 每个地区默认展示最快的条数
  static const int perRegion = 2;

  @override
  State<NodePickerSheet> createState() => _NodePickerSheetState();
}

class _NodePickerSheetState extends State<NodePickerSheet> {
  final _subscriptionService = SubscriptionService();
  List<ServerNode> _nodes = [];
  List<RegionGroup> _groups = [];
  bool _isLoading = true;
  bool _testing = false;
  String? _error;

  /// 已展开「全部」的地区
  final Set<String> _expanded = {};

  /// 本轮已测过的端点（区分「未测」与「超时」）
  final Set<String> _tested = {};
  Timer? _regroupTimer;
  int _loadGen = 0;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    SubscriptionService.lastUpdated.addListener(_onSubscriptionUpdated);
    _loadNodes();
  }

  @override
  void dispose() {
    SubscriptionService.lastUpdated.removeListener(_onSubscriptionUpdated);
    _regroupTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// 后台刷新拿到新订阅：静默换成新线路（保留已测延迟）
  void _onSubscriptionUpdated() {
    if (!mounted || _isLoading || widget.previewNodes != null) return;
    _loadNodes(silent: true);
  }

  void _regroup() {
    _groups = NodeGrouping.group(_nodes, perRegion: NodePickerSheet.perRegion);
  }

  /// 测速结果陆续到达时重排，150ms 合并一次，避免列表抖动
  void _scheduleRegroup() {
    if (_regroupTimer?.isActive ?? false) return;
    _regroupTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(_regroup);
    });
  }

  Future<void> _loadNodes({bool force = false, bool silent = false}) async {
    final gen = ++_loadGen;
    if (widget.previewNodes != null) {
      setState(() {
        _nodes = List.of(widget.previewNodes!);
        _regroup();
        _isLoading = false;
      });
      return;
    }
    if (!silent) {
      setState(() {
        _isLoading = _nodes.isEmpty;
        _error = null;
      });
    }
    try {
      // 有缓存先秒开列表（过期则后台刷新，刷新完成后自动替换）
      final nodes = await _subscriptionService.fetchNodes(
          forceRefresh: force, preferCache: !force);
      if (!mounted || gen != _loadGen) return;
      await LatencyCache.instance.load();
      LatencyCache.instance.apply(nodes, maxAge: const Duration(minutes: 30));
      setState(() {
        _nodes = List.of(nodes);
        _tested.clear();
        _regroup();
        _isLoading = false;
        _error = null;
      });
      _testAll();
    } catch (e) {
      if (mounted && gen == _loadGen) {
        setState(() {
          _isLoading = false;
          if (_nodes.isEmpty) _error = '线路加载失败，请检查网络后重试';
        });
        if (_nodes.isNotEmpty && force) {
          _toast('刷新失败，继续使用已有线路');
        }
      }
    }
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.showSnackBar(SnackBar(
        content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _refresh() async {
    HapticFeedback.lightImpact();
    await _loadNodes(force: true);
  }

  Future<void> _testAll() async {
    if (_testing || _nodes.isEmpty || widget.previewNodes != null) return;
    setState(() {
      _testing = true;
      _tested.clear();
    });
    final nodes = _nodes;
    try {
      await LatencyTestService().testAll(nodes, onResult: (updated) {
        for (final n in updated) {
          _tested.add(LatencyCache.keyOf(n));
        }
        if (mounted && identical(nodes, _nodes)) _scheduleRegroup();
      }).timeout(const Duration(seconds: 12));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      for (final n in nodes) {
        _tested.add(LatencyCache.keyOf(n));
      }
      _testing = false;
      _regroup();
    });
  }

  @override
  Widget build(BuildContext context) {
    final regions = _groups.length;
    final subtitle = _nodes.isEmpty
        ? '每个地区优先显示最快的线路'
        : '共 ${_nodes.length} 条线路 · $regions 个地区，每个地区优先显示最快 ${NodePickerSheet.perRegion} 条';
    // 固定高度的普通弹层：列表可自由滚动 / 下拉刷新；拖动顶部把手区域关闭。
    // （不用 DraggableScrollableSheet：min=max 时内部列表无法滚动，snap 时又只露出约 5 条线路）
    final h = MediaQuery.of(context).size.height * 0.88;
    return SizedBox(
      height: h,
      child: DzSheet(
        child: Column(
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 14, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('选择线路', style: DzText.title),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: DzText.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TestButton(testing: _testing, onTap: _testAll),
                  const SizedBox(width: 6),
                  GlassIconButton(
                    icon: Icons.refresh_rounded,
                    size: 38,
                    tooltip: '刷新订阅',
                    onTap: _refresh,
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(_scroll)),
          ],
        ),
      ),
    );
  }

  bool _isCurrent(ServerNode n) => NodeLabel.same(n.name, widget.currentName);

  Widget _tile(ServerNode n, int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Entrance(
        key: ValueKey('n-${n.name}'),
        delayMs: 24 * (i < 10 ? i : 10),
        dy: 10,
        child: _NodeTile(
          node: n,
          current: _isCurrent(n),
          manual: !widget.autoMode,
          testing: _testing && !_tested.contains(LatencyCache.keyOf(n)),
          tested: _tested.contains(LatencyCache.keyOf(n)) || n.latency != null,
          onTap: () {
            Navigator.pop(context);
            widget.onNodeSelected(n);
          },
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController scroll) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: AppColors.gold),
            ),
            SizedBox(height: 14),
            Text('正在获取最新线路…', style: DzText.caption),
          ],
        ),
      );
    }
    final items = <Widget>[
      _AutoTile(
        selected: widget.autoMode,
        onTap: () {
          Navigator.pop(context);
          widget.onAutoSelected?.call();
        },
      ),
      const SizedBox(height: 14),
      const Align(alignment: Alignment.centerRight, child: SubscriptionAgeLabel()),
      const SizedBox(height: 4),
    ];
    if (_error != null || _nodes.isEmpty) {
      items.add(DzEmptyState(
        icon: _error != null
            ? Icons.wifi_off_rounded
            : Icons.travel_explore_rounded,
        danger: _error != null,
        title: _error != null ? '线路加载失败' : '暂无可用线路',
        message: _error != null ? '请检查网络后重试' : '请确认套餐有效，或稍后刷新订阅',
        actionLabel: '重新获取',
        onAction: () => _loadNodes(force: true),
      ));
    } else {
      var i = 0;
      for (final g in _groups) {
        final open = _expanded.contains(g.region.code);
        final shown = open ? g.all : List.of(g.top);
        // 当前手动选择的线路即使不在前 2 名也显示出来
        if (!open) {
          for (final n in g.all.skip(g.perRegion)) {
            if (_isCurrent(n)) shown.add(n);
          }
        }
        items.add(_RegionHeader(
          group: g,
          open: open,
          onToggle: g.hiddenCount > 0
              ? () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (!_expanded.remove(g.region.code)) {
                      _expanded.add(g.region.code);
                    }
                  });
                }
              : null,
        ));
        for (final n in shown) {
          items.add(_tile(n, i++));
        }
        final hidden = g.all.length - shown.length;
        if (g.hiddenCount > 0) {
          items.add(_ExpandToggle(
            open: open,
            count: g.all.length,
            hidden: hidden,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (!_expanded.remove(g.region.code)) {
                  _expanded.add(g.region.code);
                }
              });
            },
          ));
        }
        items.add(const SizedBox(height: 8));
      }
    }
    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: const Color(0xFF111834),
      onRefresh: _refresh,
      child: ListView(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(
            18, 4, 18, 28 + MediaQuery.of(context).padding.bottom),
        children: items,
      ),
    );
  }
}

class _RegionHeader extends StatelessWidget {
  final RegionGroup group;
  final bool open;
  final VoidCallback? onToggle;
  const _RegionHeader({required this.group, this.open = false, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final best = group.bestLatency;
    final row = Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 10, bottom: 10),
      child: Row(
        children: [
          Text(group.region.flag, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(group.region.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DzText.headline.copyWith(fontSize: 15)),
          ),
          const SizedBox(width: 8),
          Text('${group.all.length} 条',
              style: DzText.caption.copyWith(fontSize: 11)),
          const Spacer(),
          if (best != null)
            Text('最快 $best ms',
                style: DzText.caption.copyWith(
                    fontSize: 11, color: AppColors.latency(best))),
          if (onToggle != null && open) ...[
            const SizedBox(width: 10),
            Text('收起',
                style: DzText.caption
                    .copyWith(fontSize: 12, color: AppColors.gold)),
          ],
        ],
      ),
    );
    if (onToggle == null) return row;
    return GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onToggle, child: row);
  }
}

class _ExpandToggle extends StatelessWidget {
  final bool open;
  final int count;
  final int hidden;
  final VoidCallback onTap;
  const _ExpandToggle(
      {required this.open,
      required this.count,
      required this.hidden,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptic: false,
      child: Container(
        height: 40,
        margin: const EdgeInsets.only(bottom: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DzRadius.md),
          border: Border.all(color: AppColors.border),
          color: Colors.white.withValues(alpha: 0.02),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                open ? '收起' : '展开全部 ($count)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: DzMotion.fast,
              child: const Icon(Icons.expand_more_rounded,
                  size: 18, color: AppColors.gold),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  final bool testing;
  final VoidCallback onTap;
  const _TestButton({required this.testing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: testing ? null : onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0x66E8C987)),
          color: AppColors.gold.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            testing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.8, color: AppColors.gold),
                  )
                : const Icon(Icons.speed_rounded,
                    size: 16, color: AppColors.gold),
            const SizedBox(width: 6),
            Text(testing ? '测速中' : '测速',
                style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _AutoTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _AutoTile({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      blur: false,
      gold: true,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: AppColors.goldGradient,
              boxShadow: [
                BoxShadow(
                    color: AppColors.goldMid.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: -4),
              ],
            ),
            child:
                const Icon(Icons.auto_awesome_rounded, color: AppColors.onGold),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GoldText('自动选择',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                SizedBox(height: 3),
                Text('毫秒级智能选线，锁定最快线路；异常自动切换下一条', style: DzText.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: DzMotion.fast,
            child: selected
                ? const Icon(Icons.check_circle_rounded,
                    key: ValueKey(1), color: AppColors.gold)
                : const Icon(Icons.radio_button_unchecked_rounded,
                    key: ValueKey(0), color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  final ServerNode node;
  final bool current;
  final bool manual;
  final bool testing;
  final bool tested;
  final VoidCallback onTap;
  const _NodeTile({
    required this.node,
    required this.current,
    required this.manual,
    required this.testing,
    required this.tested,
    required this.onTap,
  });

  static final RegExp _num = RegExp(r'\d+');

  @override
  Widget build(BuildContext context) {
    final lat = node.latency;
    final title = NodeLabel.display(node.name);
    final speed = NodeLabel.speedOf(node.name);
    final m = _num.firstMatch(title);
    final mono = m != null && m.group(0)!.length <= 3
        ? m.group(0)!
        : (title.characters.isEmpty ? '·' : title.characters.first);
    final selected = current && manual;
    return GlassCard(
      blur: false,
      gold: selected,
      radius: DzRadius.md,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                  color: selected ? AppColors.gold : AppColors.border),
            ),
            child: Text(mono,
                maxLines: 1,
                style: TextStyle(
                    fontSize: mono.length >= 3 ? 13 : 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.headline.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(_proto(node),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DzText.caption
                              .copyWith(fontSize: 10, letterSpacing: 1.1)),
                    ),
                    if (speed != null) ...[
                      const SizedBox(width: 6),
                      _Badge(text: '实测 $speed'),
                    ],
                    if (current) ...[
                      const SizedBox(width: 6),
                      Text(manual ? '已选' : '当前',
                          style: DzText.caption
                              .copyWith(fontSize: 10, color: AppColors.gold)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _LatencyPill(latency: lat, testing: testing, tested: tested),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_circle_rounded,
                color: AppColors.gold, size: 20),
          ],
        ],
      ),
    );
  }

  static String _proto(ServerNode n) {
    final p = n.protocol == 'shadowsocks' ? 'SS' : n.protocol.toUpperCase();
    final net = (n.network ?? '').toUpperCase();
    return net.isEmpty || net == 'TCP' || net == 'UDP' ? p : '$p · $net';
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: AppColors.gold.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
      ),
      child: Text(text,
          maxLines: 1,
          style: const TextStyle(
              color: AppColors.gold,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              height: 1.3)),
    );
  }
}

class _LatencyPill extends StatelessWidget {
  final int? latency;
  final bool testing;
  final bool tested;
  const _LatencyPill(
      {required this.latency, required this.testing, required this.tested});

  @override
  Widget build(BuildContext context) {
    final c = (latency == null && !tested)
        ? AppColors.textTertiary
        : AppColors.latency(latency);
    return AnimatedContainer(
      duration: DzMotion.base,
      constraints: const BoxConstraints(minWidth: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: c.withValues(alpha: 0.1),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: testing && latency == null
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: AppColors.textTertiary),
            )
          : latency == null
              ? Text(tested ? '超时' : '— ms',
                  style: TextStyle(
                      color: c, fontSize: 12, fontWeight: FontWeight.w600))
              : CountUp(
                  value: latency!.toDouble(),
                  duration: const Duration(milliseconds: 650),
                  format: (v) => '${v.round()} ms',
                  style: DzText.metricSmall.copyWith(color: c, fontSize: 12),
                ),
    );
  }
}

/// 「订阅更新于 x 分钟前」小字（每 30 秒自动刷新文案）
class SubscriptionAgeLabel extends StatefulWidget {
  const SubscriptionAgeLabel({super.key});

  @override
  State<SubscriptionAgeLabel> createState() => _SubscriptionAgeLabelState();
}

class _SubscriptionAgeLabelState extends State<SubscriptionAgeLabel> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    SubscriptionService.loadLastUpdated();
    _t = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  static String ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.isNegative || d.inMinutes < 1) return '刚刚';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SubscriptionService.lastUpdated,
        SubscriptionService.lastRefreshFailed
      ]),
      builder: (context, _) {
        final t = SubscriptionService.lastUpdated.value;
        if (t == null) return const SizedBox.shrink();
        final failed = SubscriptionService.lastRefreshFailed.value;
        final a = ago(t);
        final text = failed
            ? (a == '刚刚' ? '更新失败 · 沿用缓存线路' : '更新失败 · 沿用$a的线路')
            : (a == '刚刚' ? '订阅刚刚更新' : '订阅更新于 $a');
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(failed ? Icons.cloud_off_rounded : Icons.update_rounded,
                  size: 12,
                  color: failed
                      ? AppColors.warning.withValues(alpha: 0.75)
                      : AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(text,
                  style: DzText.caption
                      .copyWith(fontSize: 11, letterSpacing: 0.2)),
            ],
          ),
        );
      },
    );
  }
}
