import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// v1.3.0：真实出网探测。
///
/// 「已连接」以前只代表本地 VpnService / Xray 进程起来了，并不代表选中的线路真的能出网。
/// 现在隧道建立后，通过 Xray 专用探测入站（127.0.0.1:[kProbePort]，路由规则强制走 proxy
/// 出站，不受智能分流 / 远程规则影响）请求 generate_204，拿到 204 才算真正连通。
///
/// 另有一个「国内对照」探测：App 自身被排除在 VPN 之外（addDisallowedApplication），
/// 所以直连请求走手机的物理网络，用来区分「本机没网」与「线路坏了」，
/// 避免手机断网时把所有线路都误判为不可用而来回切换。

/// Xray 探测入站端口（MainActivity.buildV2rayConfig 中 tag=probe 的 HTTP 入站）
const int kProbePort = 10810;

/// 经线路出网的探测地址：任意一个返回 204 即视为连通。
/// 三个不同运营方，避免某一家被单独阻断 / Workers 类线路无法访问 Cloudflare 自家 IP 时误判。
const List<String> kEgressProbeUrls = [
  'http://www.gstatic.com/generate_204',
  'https://www.google.com/generate_204',
  'http://cp.cloudflare.com/generate_204',
];

/// 国内对照（直连，不经线路）：任意一个成功即说明本机网络正常
const List<String> kLocalProbeUrls = [
  'http://connect.rom.miui.com/generate_204',
  'http://wifi.vivo.com.cn/generate_204',
  'https://www.baidu.com/',
];

@immutable
class ProbeResult {
  final bool ok;
  final String? url;
  final int? status;
  final int? ms;
  final String? error;

  /// 平台不支持探测（桌面端等），视为通过，保持旧行为
  final bool skipped;

  const ProbeResult({
    required this.ok,
    this.url,
    this.status,
    this.ms,
    this.error,
    this.skipped = false,
  });

  const ProbeResult.skipped()
      : ok = true,
        url = null,
        status = null,
        ms = null,
        error = null,
        skipped = true;

  @override
  String toString() =>
      'ProbeResult(ok=$ok, url=$url, status=$status, ms=$ms, err=$error${skipped ? ', skipped' : ''})';
}

/// 单个 URL 的 HTTP 探测函数签名（便于单元测试替换）
typedef UrlProber = Future<ProbeResult> Function(
    String url, Duration timeout);

class EgressProbe {
  EgressProbe({
    this.proxyHost = '127.0.0.1',
    this.proxyPort = kProbePort,
    this.egressUrls = kEgressProbeUrls,
    this.localUrls = kLocalProbeUrls,
    UrlProber? viaProxy,
    UrlProber? direct,
  }) {
    _viaProxy = viaProxy ?? (u, t) => probeUrl(u, t, proxy: '$proxyHost:$proxyPort');
    _direct = direct ?? (u, t) => probeUrl(u, t);
  }

  final String proxyHost;
  final int proxyPort;
  final List<String> egressUrls;
  final List<String> localUrls;
  late final UrlProber _viaProxy;
  late final UrlProber _direct;

  /// 经线路出网：并发请求全部探测地址，第一个成功即返回；全部失败返回最后的错误。
  Future<ProbeResult> checkEgress(
      {Duration timeout = const Duration(seconds: 6)}) {
    return firstSuccess(egressUrls.map((u) => _viaProxy(u, timeout)).toList());
  }

  /// 本机网络（直连国内对照）
  Future<ProbeResult> checkLocalNetwork(
      {Duration timeout = const Duration(seconds: 4)}) {
    return firstSuccess(localUrls.map((u) => _direct(u, timeout)).toList());
  }

  /// 等任意一个成功；全部失败则返回失败结果（合并错误信息）
  static Future<ProbeResult> firstSuccess(List<Future<ProbeResult>> futures) {
    if (futures.isEmpty) {
      return Future.value(const ProbeResult(ok: false, error: 'no probe url'));
    }
    final c = Completer<ProbeResult>();
    var left = futures.length;
    final errs = <String>[];
    for (final f in futures) {
      f.then((r) {
        if (c.isCompleted) return;
        if (r.ok) {
          c.complete(r);
          return;
        }
        errs.add('${r.url ?? '?'}: ${r.status ?? r.error}');
        if (--left == 0) {
          c.complete(ProbeResult(ok: false, error: errs.join(' | ')));
        }
      }, onError: (Object e) {
        if (c.isCompleted) return;
        errs.add('$e');
        if (--left == 0) {
          c.complete(ProbeResult(ok: false, error: errs.join(' | ')));
        }
      });
    }
    return c.future;
  }

  /// 判定一次 HTTP 响应是否算「能上网」：
  /// generate_204 必须是 204（或 200 且无内容）；普通页面 2xx/3xx 即可（仅用于国内对照）。
  static bool isHealthyResponse(String url, int status, int contentLength) {
    if (url.contains('generate_204')) {
      return status == 204 || (status == 200 && contentLength == 0);
    }
    return status >= 200 && status < 400;
  }

  /// 发起一次 GET。[proxy] 形如 "127.0.0.1:10810"（Xray HTTP 入站，https 走 CONNECT）。
  /// 不跟随重定向、不读完整页面，只看状态码。
  static Future<ProbeResult> probeUrl(String url, Duration timeout,
      {String? proxy}) async {
    final sw = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 1)
      ..userAgent = 'Mozilla/5.0 (Linux; Android) DzyProbe/1.3';
    client.findProxy = (_) => proxy == null ? 'DIRECT' : 'PROXY $proxy';
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final res = await req.close().timeout(timeout);
      var len = 0;
      // 只读一小段，避免对照页面过大
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 2))) {
          len += chunk.length;
          if (len > 4096) break;
        }
      } catch (_) {}
      final ok = isHealthyResponse(url, res.statusCode, len);
      return ProbeResult(
          ok: ok, url: url, status: res.statusCode, ms: sw.elapsedMilliseconds);
    } catch (e) {
      return ProbeResult(
          ok: false,
          url: url,
          error: e.runtimeType.toString(),
          ms: sw.elapsedMilliseconds);
    } finally {
      client.close(force: true);
    }
  }
}
