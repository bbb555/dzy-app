import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一次网速采样
@immutable
class TrafficSample {
  /// 下行 / 上行速度（字节每秒）
  final double down;
  final double up;

  /// 本次连接累计（字节）
  final int totalDown;
  final int totalUp;

  const TrafficSample({
    this.down = 0,
    this.up = 0,
    this.totalDown = 0,
    this.totalUp = 0,
  });

  static const zero = TrafficSample();
}

/// 实时网速：每秒读取一次 hev-socks5-tunnel 的 TUN 累计字节数（Android 原生侧 TProxyGetStats，
/// 与 VPN 服务同进程的 JNI 计数器，无需开启 Xray stats/gRPC），相邻两次差值即速度。
///
/// - 只在「已连接 + 首页可见 + App 在前台」时轮询（由 [acquire]/[release] 引用计数控制），
///   界面不可见时完全停止；
/// - 累计流量在每次新连接时归零（[resetSession]）；计数器被重置（隧道重启）时自动续接。
class TrafficSpeedService {
  TrafficSpeedService._();
  static final TrafficSpeedService instance = TrafficSpeedService._();

  static const MethodChannel _ch = MethodChannel('com.example.flux/v2ray');

  final ValueNotifier<TrafficSample?> sample = ValueNotifier(null);

  /// 原生侧不支持（桌面端 / 读取失败）时为 false，界面隐藏网速
  final ValueNotifier<bool> supported =
      ValueNotifier(!kIsWeb && Platform.isAndroid);

  Timer? _timer;
  int _holders = 0;

  int? _lastUp, _lastDown;
  DateTime? _lastAt;
  int _sessionUp = 0, _sessionDown = 0;
  int _failures = 0;

  /// 开始轮询（可重复调用，引用计数）
  void acquire() {
    _holders++;
    if (_timer != null || !supported.value) return;
    _lastAt = null; // 暂停后恢复：第一拍只建立基线，不报一个虚高的平均速度
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  /// 停止轮询
  void release() {
    if (_holders > 0) _holders--;
    if (_holders == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// 新连接建立：累计流量归零
  void resetSession() {
    _sessionUp = 0;
    _sessionDown = 0;
    _lastAt = null;
    sample.value = TrafficSample.zero;
  }

  bool _busy = false;

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('trafficStats');
      if (r == null) {
        // 未连接：保持上一帧，速度归零
        final s = sample.value;
        if (s != null && (s.down != 0 || s.up != 0)) {
          sample.value =
              TrafficSample(totalDown: s.totalDown, totalUp: s.totalUp);
        }
        _lastAt = null;
        return;
      }
      _failures = 0;
      final up = (r['up'] as num?)?.toInt() ?? 0;
      final down = (r['down'] as num?)?.toInt() ?? 0;
      final now = DateTime.now();
      final lastAt = _lastAt;
      if (lastAt == null || _lastUp == null || _lastDown == null) {
        _lastUp = up;
        _lastDown = down;
        _lastAt = now;
        sample.value ??= TrafficSample.zero;
        return;
      }
      // 计数器变小 = 隧道重启后归零：从 0 续接
      final du = up >= _lastUp! ? up - _lastUp! : up;
      final dd = down >= _lastDown! ? down - _lastDown! : down;
      final secs = now.difference(lastAt).inMilliseconds / 1000.0;
      _lastUp = up;
      _lastDown = down;
      _lastAt = now;
      _sessionUp += du;
      _sessionDown += dd;
      // 间隔异常（> 3 秒，例如刚从后台恢复）时只累计，不计算瞬时速度
      final valid = secs > 0.2 && secs <= 3;
      final prev = sample.value ?? TrafficSample.zero;
      sample.value = TrafficSample(
        down: valid ? dd / secs : prev.down,
        up: valid ? du / secs : prev.up,
        totalDown: _sessionDown,
        totalUp: _sessionUp,
      );
    } on MissingPluginException {
      _disable();
    } catch (e) {
      if (++_failures >= 5) _disable();
    } finally {
      _busy = false;
    }
  }

  void _disable() {
    supported.value = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 测试 / 预览：直接注入一帧
  @visibleForTesting
  void debugSet(TrafficSample s) {
    supported.value = true;
    sample.value = s;
  }
}

/// 速度格式化：B/s → KB/s / MB/s
String formatSpeed(double bps) {
  final kb = bps / 1024;
  if (kb < 1000) {
    return kb < 10 ? '${kb.toStringAsFixed(1)} KB/s' : '${kb.round()} KB/s';
  }
  final mb = kb / 1024;
  return mb < 100
      ? '${mb.toStringAsFixed(2)} MB/s'
      : '${mb.toStringAsFixed(1)} MB/s';
}

/// 流量格式化
String formatBytes(int b) {
  if (b < 1024) return '$b B';
  final kb = b / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
