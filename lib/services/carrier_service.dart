import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'v2ray_service.dart';

/// v1.6.3 按运营商智能选线：识别「当前网络属于哪家运营商」。
///
/// 判定顺序（任何一步失败都往下走，绝不抛异常、绝不阻塞连接）：
/// 1. Android 本机：`flux/carrier` MethodChannel → TelephonyManager
///    （当前注册网络 `getNetworkOperator()`，WiFi/无服务时回落到 `getSimOperator()`；
///     双卡取默认数据卡；无 READ_PHONE_STATE 权限时原生返回 null）；
/// 2. 服务端兜底：与自己站点同源的明文接口（[whoamiPaths]）拿 `isp` 字段再归一化；
/// 3. 仍判不出来 → null（调用方回退 1.6.2 的排序口径）。
///
/// 缓存 30 分钟（判定失败只缓存 5 分钟，让换网后能尽快重判）；网络切换后失效重判
/// （复用 V2rayService.sinceNetworkChange 背后的原生 `netChangedAgoMs` 时间戳）。
///
/// 注意：本 App 在 FluxVpnService 里用 addDisallowedApplication 把自己排除在隧道之外，
/// 所以服务端兜底请求走的是手机物理网络，反映的是用户真实接入商，而不是节点出口。
class CarrierService {
  CarrierService({
    Future<Map<String, dynamic>?> Function()? nativeReader,
    Future<String?> Function()? ispFetcher,
    Future<Duration?> Function()? sinceNetworkChange,
    DateTime Function()? clock,
    bool? isAndroid,
  })  : _nativeReader = nativeReader,
        _ispFetcher = ispFetcher,
        _sinceNetworkChange = sinceNetworkChange,
        _clock = clock ?? DateTime.now,
        _isAndroid = isAndroid;

  /// 全局单例（缓存与单飞都在实例上）
  static final CarrierService instance = CarrierService();

  /// 原生通道名（MainActivity.configureFlutterEngine 里注册）
  static const String methodChannelName = 'flux/carrier';

  /// 归一化后的四种取值，与 [ServerNode.carrierMbps] 的键一一对应
  static const List<String> keys = ['电信', '联通', '移动', '其他'];

  /// 判定成功后的缓存时长
  static const Duration cacheTtl = Duration(minutes: 30);

  /// 判定失败（null）的缓存时长：短一些，换网 / 重开 WiFi 后能尽快重判
  static const Duration negativeTtl = Duration(minutes: 5);

  /// 服务端兜底请求超时（每个候选路径）
  static const Duration whoamiTimeout = Duration(seconds: 3);

  /// 服务端兜底候选路径（相对 `ApiConfig().getBaseUrl()`，即 `.../api/v1`）。
  ///
  /// 服务端契约：GET 返回明文 JSON，ISP 字符串放在 `data.isp` / `isp` / `as` 任一字段，
  /// 例如 `{"data":{"isp":"中国电信"}}`；不需要登录、不能被限流打死（失败即回退）。
  static const List<String> whoamiPaths = ['/guest/ipinfo', '/guest/whoami'];

  static const MethodChannel _channel = MethodChannel(methodChannelName);

  final Future<Map<String, dynamic>?> Function()? _nativeReader;
  final Future<String?> Function()? _ispFetcher;
  final Future<Duration?> Function()? _sinceNetworkChange;
  final DateTime Function() _clock;
  final bool? _isAndroid;

  String? _value;
  DateTime? _resolvedAt;
  Future<String?>? _inflight;

  bool get _supported {
    final forced = _isAndroid;
    if (forced != null) return forced;
    return !kIsWeb && Platform.isAndroid;
  }

  /// 同步读最近一次判定结果（供排序直接使用，不 await）。
  String? get value => _value;

  /// 当前运营商：`电信 / 联通 / 移动 / 其他`，判不出来返回 null。
  ///
  /// [forceRefresh] 为 true 时跳过缓存立即重判（例如用户手动刷新线路列表）。
  Future<String?> current({bool forceRefresh = false}) async {
    if (!_supported) return null;
    final running = _inflight;
    if (running != null) return running;
    final f = _resolveAndCache(forceRefresh: forceRefresh);
    _inflight = f;
    try {
      return await f;
    } catch (_) {
      return null;
    } finally {
      if (identical(_inflight, f)) _inflight = null;
    }
  }

  /// 网络切换 / 换卡后调用：丢掉缓存，下次 [current] 重新判定。
  void invalidate() {
    _value = null;
    _resolvedAt = null;
  }

  /// 仅测试用：清空缓存与单飞状态
  @visibleForTesting
  void debugReset() {
    _value = null;
    _resolvedAt = null;
    _inflight = null;
  }

  Future<String?> _resolveAndCache({required bool forceRefresh}) async {
    final since = await _sinceNetworkChangeSafe();
    if (!forceRefresh && _isFresh(since)) return _value;

    String? v;
    try {
      v = await _readNative();
    } catch (_) {
      v = null;
    }
    if (v == null) {
      try {
        v = await _readServerIsp();
      } catch (_) {
        v = null;
      }
    }

    _value = v;
    _resolvedAt = _clock();
    return v;
  }

  /// 缓存是否仍有效：TTL 未过，且缓存是「最后一次网络切换之后」的判定结果。
  bool _isFresh(Duration? sinceNetworkChange) {
    final at = _resolvedAt;
    if (at == null) return false;
    final ttl = _value == null ? negativeTtl : cacheTtl;
    final age = _clock().difference(at);
    if (age.isNegative || age > ttl) return false;
    if (sinceNetworkChange != null) {
      // sinceNetworkChange = 距上次 Wi-Fi↔移动数据切换多久；切换点晚于判定时间 → 作废
      final lastChange = _clock().subtract(sinceNetworkChange);
      if (lastChange.isAfter(at)) return false;
    }
    return true;
  }

  Future<Duration?> _sinceNetworkChangeSafe() async {
    final f = _sinceNetworkChange;
    if (f != null) {
      try {
        return await f();
      } catch (_) {
        return null;
      }
    }
    if (!_supported) return null;
    // 走既有 v2ray 通道的 netChangedAgoMs（原生记录 Wi-Fi↔移动数据切换的时刻）
    try {
      return await V2rayService().sinceNetworkChange();
    } catch (_) {
      return null;
    }
  }

  /// Android 本机判定（原生已把 MCC+MNC 映射成中文运营商名）
  Future<String?> _readNative() async {
    final injected = _nativeReader;
    if (injected != null) {
      final m = await injected();
      if (m == null) return null;
      return normalizeCarrier(m['carrier']?.toString());
    }
    try {
      final m = await _channel
          .invokeMapMethod<String, dynamic>('carrier')
          .timeout(const Duration(seconds: 2));
      if (m == null) return null;
      return normalizeCarrier(m['carrier']?.toString());
    } catch (_) {
      return null;
    }
  }

  /// 服务端兜底：明文 JSON 拿 ISP。失败/限流/超时一律 null。
  Future<String?> _readServerIsp() async {
    final injected = _ispFetcher;
    if (injected != null) return normalizeCarrier(await injected());

    String base;
    try {
      base = await ApiConfig().getBaseUrl(); // https://<域名>/api/v1
    } catch (_) {
      return null;
    }
    for (final path in whoamiPaths) {
      try {
        final r = await http
            .get(Uri.parse('$base$path'),
                headers: const {'Accept': 'application/json'})
            .timeout(whoamiTimeout);
        if (r.statusCode == 404) continue; // 该路径未部署，试下一个
        if (r.statusCode != 200) return null; // 429/403 等：直接回退，不重试
        return normalizeCarrier(_ispFromBody(r.bodyBytes));
      } catch (_) {
        // 超时 / DNS / TLS 失败：换下一个候选，最终 null
      }
    }
    return null;
  }

  static String? _ispFromBody(List<int> body) {
    try {
      final j = jsonDecode(utf8.decode(body, allowMalformed: true));
      if (j is Map) {
        final d = j['data'];
        final maps = <Map>[if (d is Map) d, j];
        for (final m in maps) {
          for (final k in const ['isp', 'isp_name', 'as', 'org']) {
            final v = m[k];
            if (v is String && v.trim().isNotEmpty) return v;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 把各种写法归一化成 `电信 / 联通 / 移动 / 其他`；认不出来返回 null。
  ///
  /// 覆盖：原生中文名、ip-api 的中文 ISP（中国电信/中国联通/中国移动/中国铁通…）、
  /// 英文（China Telecom / CHINANET / UNICOM / CMCC / CMNET …）。
  static String? normalizeCarrier(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.contains('电信') ||
        s.contains('telecom') ||
        s.contains('chinatelecom') ||
        s.contains('chinanet') ||
        s.contains('ctcc') ||
        s.contains('天翼')) {
      return '电信';
    }
    if (s.contains('联通') ||
        s.contains('unicom') ||
        s.contains('cucc') ||
        s.contains('网通')) {
      return '联通';
    }
    if (s.contains('移动') ||
        s.contains('cmcc') ||
        s.contains('cmnet') ||
        s.contains('chinamobile') ||
        s.contains('china mobile')) {
      return '移动';
    }
    // 已知「其他」：有大陆实测数据但不是三网（服务端把它们聚合到「其他」）
    if (s.contains('其他') ||
        s.contains('other') ||
        s.contains('铁通') ||
        s.contains('广电') ||
        s.contains('教育网') ||
        s.contains('长城宽带') ||
        s.contains('鹏博士') ||
        s.contains('歌华') ||
        s.contains('天威') ||
        s.contains('珠江数码') ||
        s.contains('cernet') ||
        s.contains('cbn')) {
      return '其他';
    }
    return null;
  }
}
