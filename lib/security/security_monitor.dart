import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 设备环境信号（只用于提示与固定策略判断，绝不让 App 崩溃或拒绝启动）
@immutable
class SecuritySignals {
  final bool root;
  final bool frida;
  final bool debugger;
  final bool debuggable;
  final String httpProxy;
  final int userCaCount;

  const SecuritySignals({
    this.root = false,
    this.frida = false,
    this.debugger = false,
    this.debuggable = false,
    this.httpProxy = '',
    this.userCaCount = 0,
  });

  static const none = SecuritySignals();

  /// 运行时被注入 / 调试（可绕过一切客户端防护）
  bool get instrumented => frida || debugger;

  /// 可能正在抓包：root（系统 CA 可被替换）或被注入
  bool get intercepting => root || instrumented;

  /// 抓包常见前置条件（仅提示）：设置了系统 HTTP 代理 / 安装了用户 CA
  bool get captureSetup => httpProxy.isNotEmpty || userCaCount > 0;

  factory SecuritySignals.fromMap(Map<String, dynamic> m) => SecuritySignals(
        root: m['root'] == true,
        frida: m['frida'] == true,
        debugger: m['debuggerAttached'] == true ||
            ((m['tracerPid'] as num?)?.toInt() ?? 0) > 0,
        debuggable: m['debuggable'] == true,
        httpProxy: (m['httpProxy'] ?? '').toString(),
        userCaCount: (m['userCaCount'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      'root=$root frida=$frida debugger=$debugger proxy=$httpProxy userCa=$userCaCount';
}

/// 轻量环境检测 + 固定事件记录。检测到异常只降级（提示），不阻断主流程。
class SecurityMonitor {
  SecurityMonitor._();
  static final SecurityMonitor instance = SecurityMonitor._();

  static const MethodChannel _ch = MethodChannel('com.example.flux/v2ray');

  SecuritySignals? _cached;
  DateTime? _at;
  Future<SecuritySignals>? _inflight;

  /// 需要提示用户的警告（null 为无）
  final ValueNotifier<String?> warning = ValueNotifier(null);

  final List<String> events = [];
  int pinOk = 0;

  Future<SecuritySignals> signals({bool refresh = false}) {
    if (kIsWeb || !Platform.isAndroid) return Future.value(SecuritySignals.none);
    final at = _at;
    if (!refresh &&
        _cached != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 5)) {
      return Future.value(_cached!);
    }
    return _inflight ??= () async {
      try {
        final m = await _ch
            .invokeMapMethod<String, dynamic>('securityStatus')
            .timeout(const Duration(seconds: 3));
        _cached = m == null ? SecuritySignals.none : SecuritySignals.fromMap(m);
      } catch (_) {
        _cached ??= SecuritySignals.none;
      }
      _at = DateTime.now();
      _inflight = null;
      _updateWarning();
      return _cached!;
    }();
  }

  void _updateWarning() {
    final s = _cached;
    if (s == null) return;
    if (s.instrumented) {
      warning.value = '检测到调试或注入工具，为保护账户安全，部分功能可能受限';
    } else if (s.captureSetup) {
      warning.value = s.httpProxy.isNotEmpty
          ? '检测到系统设置了 HTTP 代理，可能存在抓包风险'
          : '检测到设备安装了用户证书，可能存在抓包风险';
    }
  }

  void recordPinOk() => pinOk++;

  void recordPinEvent(String e) {
    final line = '${DateTime.now().toIso8601String()} $e';
    debugPrint('[Pin] $line');
    events.add(line);
    if (events.length > 50) events.removeAt(0);
    if (e.startsWith('blocked')) {
      warning.value = '检测到网络连接被拦截（可能存在抓包），已阻止请求以保护账户安全';
    }
  }
}
