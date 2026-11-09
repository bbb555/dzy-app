import 'package:flutter/material.dart';

import '../models/server_node.dart';
import '../services/latency_test_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_colors.dart';
import 'dz_ui.dart';

/// 线路选择弹层：顶部「自动选择」+ 全部线路（打开即并发测速，可按延迟排序）
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

  @override
  State<NodePickerSheet> createState() => _NodePickerSheetState();
}

class _NodePickerSheetState extends State<NodePickerSheet> {
  final _subscriptionService = SubscriptionService();
  List<ServerNode> _nodes = [];
  bool _isLoading = true;
  bool _testing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  Future<void> _loadNodes({bool force = false}) async {
    if (widget.previewNodes != null) {
      setState(() {
        _nodes = List.of(widget.previewNodes!);
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final nodes = await _subscriptionService.fetchNodes(forceRefresh: force);
      if (!mounted) return;
      setState(() {
        _nodes = List.of(nodes);
        _isLoading = false;
      });
      _testAll();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '线路加载失败，请下拉刷新或稍后重试';
        });
      }
    }
  }

  Future<void> _testAll() async {
    if (_testing || _nodes.isEmpty) return;
    setState(() => _testing = true);
    final tester = LatencyTestService();
    try {
      await Future.wait(_nodes.map((n) async {
        final v = await tester.testLatency(n, timeout: const Duration(seconds: 3));
        n.latency = v;
        if (mounted) setState(() {});
      })).timeout(const Duration(seconds: 6));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _nodes.sort((a, b) => (a.latency ?? 999999).compareTo(b.latency ?? 999999));
      _testing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      snap: true,
      initialChildSize: 0.66,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scroll) {
        return DzSheet(
          child: Column(
            children: [
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 14, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('选择线路', style: DzText.title),
                          SizedBox(height: 2),
                          Text('打开即自动测速，延迟越低越流畅', style: DzText.caption),
                        ],
                      ),
                    ),
                    _TestButton(testing: _testing, onTap: _testAll),
                    const SizedBox(width: 6),
                    GlassIconButton(
                      icon: Icons.refresh_rounded,
                      size: 38,
                      tooltip: '刷新订阅',
                      onTap: () => _loadNodes(force: true),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(scroll)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController scroll) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.gold),
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
      const SizedBox(height: 18),
      SectionLabel('全部线路 · ${_nodes.length}'),
    ];
    if (_error != null || _nodes.isEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text(_error ?? '暂无可用线路，请确认订阅是否有效',
              style: DzText.body, textAlign: TextAlign.center),
        ),
      ));
    } else {
      for (var i = 0; i < _nodes.length; i++) {
        final n = _nodes[i];
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Entrance(
            delayMs: 30 * (i < 12 ? i : 12),
            dy: 12,
            child: _NodeTile(
              node: n,
              current: n.name == widget.currentName,
              manual: !widget.autoMode,
              testing: _testing && n.latency == null,
              onTap: () {
                Navigator.pop(context);
                widget.onNodeSelected(n);
              },
            ),
          ),
        ));
      }
    }
    return ListView(
      controller: scroll,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(18, 4, 18, 28 + MediaQuery.of(context).padding.bottom),
      children: items,
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
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.gold),
                  )
                : const Icon(Icons.speed_rounded, size: 16, color: AppColors.gold),
            const SizedBox(width: 6),
            Text(testing ? '测速中' : '测速',
                style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600, fontSize: 13)),
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
                BoxShadow(color: AppColors.goldMid.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: -4),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: AppColors.onGold),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GoldText('自动选择', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1)),
                SizedBox(height: 3),
                Text('连接时测速选最快线路，失败自动切换（最多 3 条）', style: DzText.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: DzMotion.fast,
            child: selected
                ? const Icon(Icons.check_circle_rounded, key: ValueKey(1), color: AppColors.gold)
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
  final VoidCallback onTap;
  const _NodeTile({
    required this.node,
    required this.current,
    required this.manual,
    required this.testing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lat = node.latency;
    final ch = node.name.characters.isEmpty ? '·' : node.name.characters.first;
    final selected = current && manual;
    return GlassCard(
      blur: false,
      gold: selected,
      radius: DzRadius.md,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(ch,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.headline.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(node.protocol.toUpperCase(),
                        style: DzText.caption.copyWith(fontSize: 10, letterSpacing: 1.2)),
                    if (current) ...[
                      const SizedBox(width: 8),
                      Text(manual ? '已选' : '当前', style: DzText.caption.copyWith(fontSize: 10, color: AppColors.gold)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _LatencyPill(latency: lat, testing: testing),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 20),
          ],
        ],
      ),
    );
  }
}

class _LatencyPill extends StatelessWidget {
  final int? latency;
  final bool testing;
  const _LatencyPill({required this.latency, required this.testing});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.latency(latency);
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
      child: testing
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.textTertiary),
            )
          : latency == null
              ? Text('超时', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600))
              : CountUp(
                  value: latency!.toDouble(),
                  duration: const Duration(milliseconds: 650),
                  format: (v) => '${v.round()} ms',
                  style: DzText.metricSmall.copyWith(color: c, fontSize: 12),
                ),
    );
  }
}
