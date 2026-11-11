import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 本机流量用量（v1.3.0）。
///
/// 官网是**时长套餐**，服务器不统计每用户流量（/user/getSubscribe 的 u/d 恒为 0，getStat 恒为 [0,0,0]），
/// 所以「已用流量」改为读取本机 VPN 通道（hev-socks5-tunnel TUN 计数器）的真实字节数：
/// - 本次：用户这一次点击「连接」以来（自动切换线路导致的隧道重建算同一次）；
/// - 累计：本机自 [since] 起的总和，持久化在原生 SharedPreferences（每 15 秒检查点 + 断开时结转）。
@immutable
class UsageStats {
  final int sessionUp;
  final int sessionDown;
  final int totalUp;
  final int totalDown;

  /// 累计起始时间（首次连接 / 用户清零）
  final DateTime? since;
  final bool running;

  const UsageStats({
    this.sessionUp = 0,
    this.sessionDown = 0,
    this.totalUp = 0,
    this.totalDown = 0,
    this.since,
    this.running = false,
  });

  int get session => sessionUp + sessionDown;
  int get total => totalUp + totalDown;

  static UsageStats fromMap(Map<String, dynamic> m) {
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    final s = i('since');
    return UsageStats(
      sessionUp: i('sessionUp'),
      sessionDown: i('sessionDown'),
      totalUp: i('totalUp'),
      totalDown: i('totalDown'),
      since: s > 0 ? DateTime.fromMillisecondsSinceEpoch(s) : null,
      running: m['running'] == true,
    );
  }
}

class UsageService {
  UsageService._();
  static final UsageService instance = UsageService._();

  static const MethodChannel _ch = MethodChannel('com.example.flux/v2ray');

  final ValueNotifier<UsageStats?> stats = ValueNotifier(null);
  final ValueNotifier<bool> supported =
      ValueNotifier(!kIsWeb && Platform.isAndroid);

  Timer? _timer;
  int _holders = 0;
  bool _busy = false;

  /// 界面可见时轮询（引用计数，与 TrafficSpeedService 同样的节流方式）
  void acquire({Duration every = const Duration(seconds: 2)}) {
    _holders++;
    if (_timer != null || !supported.value) return;
    refresh();
    _timer = Timer.periodic(every, (_) => refresh());
  }

  void release() {
    if (_holders > 0) _holders--;
    if (_holders == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<UsageStats?> refresh() async {
    if (!supported.value || _busy) return stats.value;
    _busy = true;
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('usageStats');
      if (m != null) stats.value = UsageStats.fromMap(m);
    } on MissingPluginException {
      supported.value = false;
      _timer?.cancel();
      _timer = null;
    } catch (e) {
      debugPrint('[Usage] refresh failed: $e');
    } finally {
      _busy = false;
    }
    return stats.value;
  }

  /// 用户发起新连接：本次用量归零（自动切换线路时不调用）
  Future<void> beginSession() async {
    if (!supported.value) return;
    try {
      await _ch.invokeMethod('usageBeginSession');
    } catch (_) {}
    await refresh();
  }

  /// 清零本机累计
  Future<void> resetTotal() async {
    if (!supported.value) return;
    try {
      await _ch.invokeMethod('usageReset');
    } catch (_) {}
    await refresh();
  }

  @visibleForTesting
  void debugSet(UsageStats s) {
    supported.value = true;
    stats.value = s;
  }
}
