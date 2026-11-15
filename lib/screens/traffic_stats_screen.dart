import 'package:flutter/material.dart';

import '../services/daily_usage_service.dart';
import '../services/usage_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/dz_ui.dart';

/// v1.5.8 流量统计页：
/// 今日用量 + 最近 7 日趋势柱状图 + 按线路维度用量 Top。
/// 数据来自 [DailyUsageService]（纯客户端本地统计）。
class TrafficStatsScreen extends StatefulWidget {
  const TrafficStatsScreen({super.key});

  @override
  State<TrafficStatsScreen> createState() => _TrafficStatsScreenState();
}

class _TrafficStatsScreenState extends State<TrafficStatsScreen> {
  late final DailyUsageService _svc = DailyUsageService.instance;

  @override
  void initState() {
    super.initState();
    _svc.start();
    _svc.revision.addListener(_onRev);
  }

  void _onRev() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _svc.revision.removeListener(_onRev);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final daily = _svc.dailyForLastDays(7);
    final today = _svc.todayBytes();
    final lines = _svc.linesTop(8);
    final lineTotal =
        lines.fold<int>(0, (n, e) => n + (e['bytes'] as int));
    final session =
        UsageService.instance.stats.value?.session ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('流量统计'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ── 今日用量大字卡 ──
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.today_rounded,
                          size: 16, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Text('今日用量',
                          style: DzText.caption
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(Formatters.formatBytes(today),
                      style: DzText.metric.copyWith(
                          fontSize: 32, color: AppColors.goldLight)),
                  const SizedBox(height: 6),
                  Text('本次连接已用 ${Formatters.formatBytes(session)}',
                      style:
                          DzText.caption.copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── 最近 7 日趋势 ──
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('最近 7 日',
                      style: DzText.caption
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: _BarChart(data: daily),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── 线路维度用量 ──
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route_rounded,
                          size: 16, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Text('线路用量 Top',
                          style: DzText.caption
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (lines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('连接后才能统计各线路用量',
                          style: DzText.caption
                              .copyWith(color: AppColors.textTertiary)),
                    )
                  else
                    for (var i = 0; i < lines.length; i++) ...[
                      _LineRow(
                        rank: i + 1,
                        name: lines[i]['line'] as String,
                        bytes: lines[i]['bytes'] as int,
                        ratio: lineTotal == 0
                            ? 0.0
                            : (lines[i]['bytes'] as int) / lineTotal,
                      ),
                      if (i != lines.length - 1) const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text('清空统计'),
                    content: const Text('将清空本地统计的每日与线路用量（不影响本次连接），确定？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('取消',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('清空',
                            style: TextStyle(color: AppColors.warning)),
                      ),
                    ],
                  ),
                );
                if (ok == true) await _svc.clearAll();
              },
              icon: Icon(Icons.delete_sweep_rounded,
                  size: 15, color: AppColors.warning),
              label: Text('清空本地统计',
                  style: TextStyle(color: AppColors.warning)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 7 日柱状图（纯 CustomPaint，无第三方依赖）
class _BarChart extends StatelessWidget {
  final List<Map<String, Object>> data;
  const _BarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return CustomPaint(
        size: Size(box.maxWidth, box.maxHeight),
        painter: _BarChartPainter(data),
      );
    });
  }
}

class _BarChartPainter extends CustomPainter {
  final List<Map<String, Object>> data;
  _BarChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = data.fold<int>(0, (n, e) {
      final v = e['bytes'] as int;
      return v > n ? v : n;
    });
    final barArea = size.height - 22; // 底部留标签
    final slot = size.width / data.length;
    final barW = slot * 0.55;

    for (var i = 0; i < data.length; i++) {
      final v = data[i]['bytes'] as int;
      final label = data[i]['label'] as String;
      final cx = slot * i + slot / 2;

      final h = maxV == 0 ? 2.0 : (v / maxV) * barArea;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, barArea - h, barW, h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8C987), Color(0x66E8C987)],
        ).createShader(
            Rect.fromLTWH(cx - barW / 2, barArea - h, barW, h));
      canvas.drawRRect(rect, paint);

      // 标签
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, barArea + 6));
    }

    // 基准线
    final line = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, barArea), Offset(size.width, barArea), line);
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.data.length != data.length ||
      !old.data.every((e) => data.contains(e));
}

/// 单条线路用量行
class _LineRow extends StatelessWidget {
  final int rank;
  final String name;
  final int bytes;
  final double ratio;

  const _LineRow({
    required this.rank,
    required this.name,
    required this.bytes,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: Text('$rank',
              style: DzText.caption.copyWith(
                  fontSize: 10, color: AppColors.gold)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DzText.caption
                    .copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.glassStrong,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.gold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(Formatters.formatBytes(bytes),
            style: DzText.caption.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}