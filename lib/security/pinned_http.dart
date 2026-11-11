import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'pinned_roots.dart';
import 'security_monitor.dart';

/// v1.3.0 控制面 TLS 固定（防抓包）。
///
/// **只作用于 App 自身的控制面请求**（官网 API、订阅下载、更新清单与安装包，主机为
/// `dzgg666.de5.net` 及其子域）。用户经 VPN 隧道的代理流量由独立的 Xray 进程处理，与此无关；
/// App 进程本身也被排除在 VPN 之外（addDisallowedApplication）。
///
/// 做法：控制面请求使用一个**只信任少量公共根 CA**（Google Trust Services / GlobalSign /
/// Let's Encrypt ISRG / SSL.com / Sectigo-USERTrust / DigiCert，见 [kPinnedRootSpki]）的
/// SecurityContext。Cloudflare Universal SSL 会在这些 CA 之间轮换叶子与中间证书，
/// 只固定根（而不是叶子）就不会因为轮换把 App 锁死；抓包工具装进系统证书库的自签 CA 不在其中，握手直接失败。
///
/// 失败策略（不把 App 搞砖）：
/// - 固定校验失败、但系统信任库能通过，且设备**没有** root / Frida / 调试器信号 →
///   多半是 Cloudflare 换到了名单外的新 CA：放行（fail-open），记录日志并计数；
/// - 同样情况但设备存在 root / Frida 信号（抓包所需的系统 CA 只能在 root 设备上安装）→
///   视为被拦截，拒绝请求并在界面提示。
///
/// 由于 Dart 的 HttpClient 不读取 Android 的「用户证书」也不走系统 HTTP 代理，
/// 普通「装个 Charles 证书 + 设 Wi-Fi 代理」的抓包方式原本就截不到 App 请求；这层固定主要防的是
/// root 设备上把 CA 装进系统库的中间人。
class PinnedHttp {
  PinnedHttp._();

  /// 受保护的控制面主域（含所有子域）
  static const List<String> pinnedDomains = ['dzgg666.de5.net'];

  /// 编译期开关：--dart-define=DZY_PIN_MODE=off|soft|enforce（默认 soft，见上方失败策略）
  static const String mode =
      String.fromEnvironment('DZY_PIN_MODE', defaultValue: 'soft');

  static bool isPinnedHost(String host) {
    final h = host.toLowerCase();
    return pinnedDomains.any((d) => h == d || h.endsWith('.$d'));
  }

  static SecurityContext? _ctx;

  /// 只信任固定根 CA 的 SecurityContext（加载失败返回 null → 调用方回退系统信任）
  static SecurityContext? get pinnedContext {
    if (_ctx != null) return _ctx;
    try {
      final c = SecurityContext(withTrustedRoots: false);
      c.setTrustedCertificatesBytes(kPinnedRootsPem.codeUnits);
      _ctx = c;
    } catch (e) {
      debugPrint('[Pin] failed to load pinned roots: $e');
      SecurityMonitor.instance.recordPinEvent('roots_load_failed');
    }
    return _ctx;
  }

  /// 新建 dart:io HttpClient：控制面主机用固定上下文，其它主机用系统默认
  static HttpClient newHttpClient({bool pinned = true}) {
    final ctx = pinned && mode != 'off' ? pinnedContext : null;
    return ctx == null ? HttpClient() : HttpClient(context: ctx);
  }

  /// 是否为证书校验失败（而非普通网络错误）
  static bool isCertFailure(Object e) {
    if (e is HandshakeException || e is TlsException) {
      // 只认证书校验失败；握手中途被重置（运营商 / 防火墙干扰）是普通网络错误，
      // 不能当成「被抓包」——否则 root 设备遇到一次 RST 就会被误判拦截
      final s = e.toString().toUpperCase();
      return s.contains('CERTIFICATE') || s.contains('VERIFY');
    }
    return false;
  }

  /// 固定校验失败后是否允许回退到系统信任（fail-open）
  static Future<bool> allowFallback() async {
    if (mode == 'off') return true;
    if (mode == 'enforce') return false;
    final sig = await SecurityMonitor.instance.signals();
    return !sig.intercepting;
  }

  /// 统一执行：控制面主机先走固定客户端；证书失败时按策略回退系统信任。
  /// [send] 拿到一个 http.Client 并完成请求。
  static Future<T> run<T>(
      Uri uri, Future<T> Function(http.Client client) send) async {
    if (!isPinnedHost(uri.host) || mode == 'off' || uri.scheme != 'https') {
      final c = http.Client();
      try {
        return await send(c);
      } finally {
        c.close();
      }
    }
    final pinned = IOClient(newHttpClient());
    try {
      final r = await send(pinned);
      SecurityMonitor.instance.recordPinOk();
      return r;
    } catch (e) {
      if (!isCertFailure(e)) rethrow;
      debugPrint('[Pin] pinned TLS failed for ${uri.host}: $e');
      if (!await allowFallback()) {
        SecurityMonitor.instance.recordPinEvent('blocked:${uri.host}');
        throw const PinViolation();
      }
      // 回退系统信任：若系统也不认 → 原样抛出普通网络错误；若系统认 → 记录「名单外 CA」
      final sys = http.Client();
      try {
        final r = await send(sys);
        SecurityMonitor.instance.recordPinEvent('fail_open:${uri.host}');
        return r;
      } finally {
        sys.close();
      }
    } finally {
      pinned.close();
    }
  }

  static final Map<String, DateTime> _verifiedAt = {};
  static final Map<String, bool> _verifiedPinned = {};

  /// dart:io HttpClient 版本（更新清单 / 安装包下载等流式场景）：
  /// 先用固定上下文做一次 TLS 握手预检（10 分钟内同主机复用结论），
  /// 通过 → 返回固定客户端；证书不通过 → 按失败策略返回系统信任客户端或抛 [PinViolation]。
  static Future<HttpClient> clientFor(Uri uri) async {
    final usePin =
        isPinnedHost(uri.host) && mode != 'off' && uri.scheme == 'https';
    if (!usePin) return HttpClient();
    final key = uri.host.toLowerCase();
    final at = _verifiedAt[key];
    if (at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 10)) {
      return newHttpClient(pinned: _verifiedPinned[key] ?? true);
    }
    final ctx = pinnedContext;
    if (ctx == null) return HttpClient();
    try {
      final sock = await SecureSocket.connect(uri.host, uri.hasPort ? uri.port : 443,
              context: ctx, timeout: const Duration(seconds: 8))
          .timeout(const Duration(seconds: 10));
      sock.destroy();
      _verifiedAt[key] = DateTime.now();
      _verifiedPinned[key] = true;
      SecurityMonitor.instance.recordPinOk();
      return newHttpClient();
    } catch (e) {
      if (!isCertFailure(e)) {
        // 普通网络错误：交给后续真实请求去报错
        return newHttpClient();
      }
      debugPrint('[Pin] pinned TLS failed for ${uri.host}: $e');
      if (!await allowFallback()) {
        SecurityMonitor.instance.recordPinEvent('blocked:${uri.host}');
        throw const PinViolation();
      }
      SecurityMonitor.instance.recordPinEvent('fail_open:${uri.host}');
      _verifiedAt[key] = DateTime.now();
      _verifiedPinned[key] = false;
      return HttpClient();
    }
  }
}

class PinViolation implements Exception {
  const PinViolation();
  @override
  String toString() => '检测到网络连接被拦截（可能存在抓包或代理），已阻止本次请求以保护账户安全';
}
