import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'usage_service.dart';

/// v1.5.8 流量统计：每日用量 + 按线路维度用量。
///
/// 完全基于 [UsageService] 的累计计数器做差分（纯 Dart，无需改原生层）：
/// 每 5 秒轮询一次累计 total，与上次记录点之差记入「今日」桶与「当前线路」桶。
/// 数据持久化在 SharedPreferences（保留最近 30 天 / 最近 40 条线路）。
///
/// 注意：原生计数器只有 up+down 汇总值，无法区分上下行，故只统计总量。
class DailyUsageService {
  DailyUsageService._();
  static final DailyUsageService instance = DailyUsageService._();

  static const _kDaysKey = 'daily_usage_days_v2';
  static const _kLinesKey = 'daily_usage_lines_v2';
  static const _kLastPointKey = 'daily_usage_lastpoint_v2';

  Timer? _timer;
  int _ticksSinceFlush = 0;
  int _lastTotal = 0;
  bool _started = false;

  /// 当前线路的稳定名称（由调用方在切线时注入）
  String? _currentLine;

  /// 数据版本号：任意一天/一条线路变化时 +1，供 UI 重建
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// date('MM-dd') -> {down: bytes}
  final Map<String, Map<String, int>> _days = {};

  /// stableName -> {down: bytes}
  final Map<String, Map<String, int>> _lines = {};

  void setCurrentLine(String? stableName) => _currentLine = stableName;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _load();
    final prefs = await SharedPreferences.getInstance();
    _lastTotal = prefs.getInt(_kLastPointKey) ?? 0;
    revokeIfCleared();
    _tick(); // 立即补记一次
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    _timer = null;
    _flush();
  }

  /// 一次性/一次性清零（内存与磁盘一起清）
  Future<void> clearAll() async {
    _days.clear();
    _lines.clear();
    _lastTotal = 0;
    revision.value++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDaysKey);
    await prefs.remove(_kLinesKey);
    await prefs.remove(_kLastPointKey);
  }

  /// 外部清零累计用量后：重设基准点，避免一次性误记巨量
  Future<void> revokeIfCleared() async {
    final s = UsageService.instance.stats.value;
    if (s == null) return;
    final total = s.total;
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt(_kLastPointKey) ?? 0;
    // 运维/用户清零后 total 回落明显时，以新值为基准
    if (prev > total && prev - total > (1 << 20)) {
      _lastTotal = total;
      await prefs.setInt(_kLastPointKey, total);
    }
  }

  Future<void> _tick() async {
    final s = await UsageService.instance.refresh();
    if (s == null) return; // 不支持（桌面）或未就绪
    final total = s.total;
    if (total < _lastTotal) {
      // 累计被清零：重设基准
      _lastTotal = total;
      return;
    }
    if (total == _lastTotal) return;
    final diff = total - _lastTotal;
    _lastTotal = total;

    final now = DateTime.now();
    final d = '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    (_days.putIfAbsent(d, () => {'down': 0}))['down'] =
        (_days[d]!['down'] ?? 0) + diff;

    final line = _currentLine;
    if (line != null && line.isNotEmpty) {
      (_lines.putIfAbsent(line, () => {'down': 0}))['down'] =
          (_lines[line]!['down'] ?? 0) + diff;
    }

    revision.value++;
    if (++_ticksSinceFlush >= 6) _flush(); // 约每 30 秒落盘
  }

  /// 过去 [days] 天的每日用量（含 0 天），从旧到新
  List<Map<String, Object>> dailyForLastDays(int days) {
    final out = <Map<String, Object>>[];
    final now = DateTime.now();
    for (var i = days - 1; i >= 0; i--) {
      final t = now.subtract(Duration(days: i));
      final d = '${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')}';
      final v = _days[d]?['down'] ?? 0;
      out.add({'label': '${t.month}/${t.day}', 'bytes': v});
    }
    return out;
  }

  int todayBytes() => dailyForLastDays(1).first['bytes'] as int;

  /// 按线路用量降序（最多 [limit] 条）
  List<Map<String, Object>> linesTop(int limit) {
    final list = _lines.entries.toList()
      ..sort((a, b) => (b.value['down'] ?? 0).compareTo(a.value['down'] ?? 0));
    return list.take(limit).map((e) {
      return {'line': e.key, 'bytes': e.value['down'] ?? 0};
    }).toList();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dj = prefs.getString(_kDaysKey);
    final lj = prefs.getString(_kLinesKey);
    if (dj != null) {
      try {
        final m = (jsonDecode(dj) as Map).cast<String, dynamic>();
        m.forEach((k, v) => _days[k] = Map<String, int>.from(v as Map));
      } catch (_) {}
    }
    if (lj != null) {
      try {
        final m = (jsonDecode(lj) as Map).cast<String, dynamic>();
        m.forEach((k, v) => _lines[k] = Map<String, int>.from(v as Map));
      } catch (_) {}
    }
    _prune();
  }

  Future<void> _flush() async {
    _ticksSinceFlush = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDaysKey, jsonEncode(_days));
    await prefs.setString(_kLinesKey, jsonEncode(_lines));
    await prefs.setInt(_kLastPointKey, _lastTotal);
  }

  void _prune() {
    // 只保留最近 30 天的键
    final now = DateTime.now();
    final keep = <String>{};
    for (var i = 0; i < 30; i++) {
      final t = now.subtract(Duration(days: i));
      keep.add(
          '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}');
    }
    _days.removeWhere((k, _) => !keep.contains(k));
    final entries = _lines.entries.toList()
      ..sort((a, b) => (b.value['down'] ?? 0).compareTo(a.value['down'] ?? 0));
    if (entries.length > 40) {
      for (final e in entries.skip(40)) {
        _lines.remove(e.key);
      }
    }
  }
}