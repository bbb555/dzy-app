import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../security/pinned_http.dart';
import 'api_config.dart';
import '../models/invite_data.dart';
import '../utils/user_agent_utils.dart';

class V2BoardApiException implements Exception {
  V2BoardApiException({
    required this.statusCode,
    required this.message,
    this.body,
  });

  final int statusCode;
  final String message;
  final String? body;

  @override
  String toString() => message;
}

class V2BoardApi {
  V2BoardApi({ApiConfig? config}) : _config = config ?? ApiConfig();

  final ApiConfig _config;

  Future<Map<String, dynamic>> getPlans() async {
    try {
      // Some deployments disable guest routes; prefer authed route when available.
      return await _get('/user/plan/fetch');
    } on V2BoardApiException catch (e) {
      if (e.statusCode == 404) {
        return _get('/guest/plan/fetch', withAuth: false);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getGuestPlans() async {
    return _get('/guest/plan/fetch', withAuth: false);
  }

  Future<Map<String, dynamic>> getGuestConfig() async {
    return _get('/guest/common/config', withAuth: false);
  }

  Future<Map<String, dynamic>> getUserCommonConfig() async {
    return _get('/user/comm/config');
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    return _post('/passport/auth/login', {
      'email': email,
      'password': password,
    }, withAuth: false);
  }

  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
    String? recaptchaData,
  }) async {
    return _post('/passport/auth/register', {
      'email': email,
      'password': password,
      if (inviteCode?.isNotEmpty == true) 'invite_code': inviteCode!,
      if (emailCode?.isNotEmpty == true) 'email_code': emailCode!,
      if (recaptchaData?.isNotEmpty == true) 'recaptcha_data': recaptchaData!,
    }, withAuth: false);
  }

  Future<Map<String, dynamic>> authCheck() async {
    return _get('/passport/auth/check');
  }

  Future<Map<String, dynamic>> forgetPassword(
    String email,
    String emailCode,
    String password,
  ) async {
    return _post('/passport/auth/forget', {
      'email': email,
      'email_code': emailCode,
      'password': password,
    }, withAuth: false);
  }

  /// AES-128 ECB 加密密钥 (用于 sendEmailVerify 接口)
  /// TODO: Replace with your V2Board email verify key (16 characters)
  static const String _emailVerifyKey = 'YOUR_16CHAR_KEY!';

  Future<Map<String, dynamic>> sendEmailVerify(
    String email, {
    String? recaptchaData,
    int isForget = 0,
    bool useEncryption = true, // 默认启用加密
  }) async {
    if (useEncryption) {
      // 构建原始 payload
      final payload = <String, dynamic>{
        'email': email,
        'isforget': isForget,
        if (recaptchaData?.isNotEmpty == true) 'recaptcha_data': recaptchaData!,
      };

      // AES-128 ECB 加密
      final key = encrypt_pkg.Key.fromUtf8(_emailVerifyKey);
      final encrypter = encrypt_pkg.Encrypter(
        encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.ecb),
      );
      final jsonString = jsonEncode(payload);
      final encrypted = encrypter.encrypt(jsonString);

      // 调试输出
      if (kDebugMode) {
        print('[sendEmailVerify] payload: $jsonString');
        print('[sendEmailVerify] encrypted: ${encrypted.base64}');
      }

      // 发送加密后的 params
      return _post('/passport/comm/sendEmailVerify', {
        'params': encrypted.base64,
      }, withAuth: false);
    } else {
      // 非加密模式 (原版)
      return _post('/passport/comm/sendEmailVerify', {
        'email': email,
        if (recaptchaData?.isNotEmpty == true) 'recaptcha_data': recaptchaData!,
      }, withAuth: false);
    }
  }

  Future<Map<String, dynamic>> getTempToken() async {
    return _post('/passport/auth/getTempToken', {}, withAuth: false);
  }

  Future<Map<String, dynamic>> getAppConfig() async {
    // 有些面板会要求 token，这里默认携带
    return _get('/client/app/getConfig');
  }

  Future<Map<String, dynamic>> getAppVersion() async {
    // 有些面板会要求 token，这里默认携带
    return _get('/client/app/getVersion');
  }

  Future<Map<String, dynamic>> getClientSubscribe({String? flag}) async {
    // 根据API文档，/client/subscribe需要认证
    return _get(
      '/client/subscribe',
      query: {if (flag?.isNotEmpty == true) 'flag': flag!},
      withAuth: true,
    );
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    return _get('/user/info');
  }

  Future<Map<String, dynamic>> getUserSubscribe() async {
    return _get('/user/getSubscribe');
  }

  Future<Map<String, dynamic>> fetchNotice() async {
    return _get('/user/notice/fetch');
  }

  Future<Map<String, dynamic>> logout() async {
    return _get('/user/logout');
  }

  Future<Map<String, dynamic>> getPlanDetail(String id) async {
    return _get('/user/plan/fetch', query: {'id': id});
  }

  Future<Map<String, dynamic>> saveOrder(
    int planId,
    String period, {
    String? couponCode,
  }) async {
    return _post('/user/order/save', {
      'plan_id': planId.toString(),
      'period': period,
      if (couponCode?.isNotEmpty == true) 'coupon_code': couponCode!,
    });
  }

  Future<Map<String, dynamic>> checkoutOrder(
    String tradeNo,
    int methodId,
  ) async {
    return _post('/user/order/checkout', {
      'trade_no': tradeNo,
      'method': methodId.toString(),
    });
  }

  Future<Map<String, dynamic>> checkOrder(String tradeNo) async {
    return _get('/user/order/check', query: {'trade_no': tradeNo});
  }

  Future<Map<String, dynamic>> getPaymentMethods() async {
    return _get('/user/order/getPaymentMethod');
  }

  /// 取消订单
  Future<Map<String, dynamic>> cancelOrder(String tradeNo) async {
    return _post('/user/order/cancel', {'trade_no': tradeNo});
  }

  /// 获取订单列表
  Future<Map<String, dynamic>> fetchOrders() async {
    return _get('/user/order/fetch');
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    bool withAuth = true,
  }) async {
    return _getWithRetry(
      path,
      query: query,
      withAuth: withAuth,
      didRetry: false,
    );
  }

  Future<Map<String, dynamic>> _getWithRetry(
    String path, {
    required Map<String, String>? query,
    required bool withAuth,
    required bool didRetry,
  }) async {
    int retryCount = 0;
    const maxRetries = 2;
    while (true) {
      try {
        final uri = await _buildUri(path, query);
        final headers = await _headers(withAuth: withAuth);
        _log('GET', uri.toString(), headers: headers);
        final response = await PinnedHttp.run(
                uri, (c) => c.get(uri, headers: headers))
            .timeout(const Duration(seconds: 20));
        _logResponse(response, uri.toString());
        if (!didRetry &&
            withAuth &&
            response.statusCode == 403 &&
            response.body.contains('token is null')) {
          _log(
            'INFO',
            'token is null, refreshing auth cache and retrying $uri',
          );
          await _config.refreshAuthCache();
          return _getWithRetry(
            path,
            query: query,
            withAuth: withAuth,
            didRetry: true,
          );
        }
        return _handle(response, context: uri.toString());
      } catch (e) {
        if (retryCount < maxRetries &&
            (e is HandshakeException || e is SocketException)) {
          retryCount++;
          _log('RETRY', 'Attempt $retryCount failed for $path: $e');
          await Future.delayed(Duration(seconds: 1 * retryCount));
          continue;
        }
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool withAuth = true,
  }) async {
    return _postWithRetry(path, body, withAuth: withAuth, didRetry: false);
  }

  Future<Map<String, dynamic>> _postWithRetry(
    String path,
    Map<String, dynamic> body, {
    required bool withAuth,
    required bool didRetry,
  }) async {
    int retryCount = 0;
    const maxRetries = 2;
    while (true) {
      try {
        final uri = await _buildUri(path, null);
        final headers = await _headers(withAuth: withAuth);
        headers['Content-Type'] = 'application/json';
        _log(
          'POST',
          uri.toString(),
          headers: headers,
          body: body.map((k, v) => MapEntry(k, v.toString())),
        );
        final payload = jsonEncode(body);
        final response = await PinnedHttp.run(
                uri, (c) => c.post(uri, headers: headers, body: payload))
            .timeout(const Duration(seconds: 20));
        _logResponse(response, uri.toString());
        if (!didRetry &&
            withAuth &&
            response.statusCode == 403 &&
            response.body.contains('token is null')) {
          _log(
            'INFO',
            'token is null, refreshing auth cache and retrying $uri',
          );
          await _config.refreshAuthCache();
          return _postWithRetry(path, body, withAuth: withAuth, didRetry: true);
        }
        return _handle(response, context: uri.toString());
      } catch (e) {
        if (retryCount < maxRetries &&
            (e is HandshakeException || e is SocketException)) {
          retryCount++;
          _log('RETRY', 'Attempt $retryCount failed for $path: $e');
          await Future.delayed(Duration(seconds: 1 * retryCount));
          continue;
        }
        rethrow;
      }
    }
  }

  Future<Map<String, String>> _headers({bool withAuth = true}) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': UserAgentUtils.userAgent,
    };
    if (!withAuth) return headers;

    // 确保缓存最新
    await _config.refreshAuthCache();

    final token = await _config.getToken();
    final authData = await _config.getAuthData();

    // 优先使用 token 作为 api_key
    if (token != null && token.isNotEmpty) {
      headers['api_key'] = token;
    } else if (authData != null && authData.isNotEmpty) {
      // 部分接口只检查 api_key，这里兜底用 auth_data
      headers['api_key'] = authData;
    }

    if (authData != null && authData.isNotEmpty) {
      headers['Authorization'] = authData;
    }
    return headers;
  }

  Future<Uri> _buildUri(String path, Map<String, String>? query) async {
    final base = await _config.getBaseUrl();
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return Uri.parse('$normalized$path').replace(queryParameters: query);
  }

  Map<String, dynamic> _handle(http.Response response, {String? context}) {
    final body = response.body;
    if (response.statusCode >= 500) {
      final message = _extractErrorMessage(body) ?? '服务器繁忙，请稍后重试';
      throw V2BoardApiException(
        statusCode: response.statusCode,
        message: message,
        body: body,
      );
    }
    if (response.statusCode >= 400) {
      final message =
          _extractErrorMessage(body) ?? (body.isNotEmpty ? body : '请求失败');
      throw V2BoardApiException(
        statusCode: response.statusCode,
        message: message,
        body: body.isEmpty ? null : body,
      );
    }
    if (body.isEmpty) {
      return {'status': response.statusCode};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'data': decoded};
    } catch (_) {
      // Some endpoints return plain text (e.g. base64 subscription string).
      return {'data': body};
    }
  }

  String? _extractErrorMessage(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;

    // Prefer JSON { message: ... }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is Map) {
          for (final entry in errors.entries) {
            final value = entry.value;
            if (value is List && value.isNotEmpty) {
              final msg = value.first?.toString();
              if (msg != null && msg.trim().isNotEmpty) return msg.trim();
            }
            if (value is String && value.trim().isNotEmpty) return value.trim();
          }
        }
        final msg = decoded['message']?.toString();
        if (msg != null && msg.trim().isNotEmpty) return msg.trim();
      }
    } catch (_) {
      // ignore
    }

    // Common nginx HTML error pages
    final titleMatch = RegExp(
      r'<title>([^<]+)</title>',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (titleMatch != null) return titleMatch.group(1)?.trim();
    final h1Match = RegExp(
      r'<h1>([^<]+)</h1>',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (h1Match != null) return h1Match.group(1)?.trim();

    return null;
  }

  void _log(
    String method,
    String url, {
    Map<String, String>? headers,
    Map<String, String>? body,
  }) {
    if (!kDebugMode) return;
    // NOTE: api_key 可能包含敏感信息，如需隐藏可做屏蔽
    final safeHeaders = {...?headers};
    if (safeHeaders.containsKey('api_key')) {
      safeHeaders['api_key'] = '***';
    }
    if (safeHeaders.containsKey('Authorization')) {
      safeHeaders['Authorization'] = '***';
    }
    print('[FluxAPI] $method $url');
    print('[FluxAPI] headers: $safeHeaders');
    if (body != null) print('[FluxAPI] body: $body');
  }

  // Invite Management
  Future<InviteFetchData> fetchInviteData() async {
    final response = await _get('/user/invite/fetch');
    // response is already Map<String, dynamic>
    final data = response['data'];
    return InviteFetchData.fromJson(data);
  }

  Future<void> generateInviteCode() async {
    await _get('/user/invite/save');
  }

  Future<List<InviteDetail>> fetchInviteDetails() async {
    final response = await _get('/user/invite/details');
    // response is already Map<String, dynamic>
    final data = response['data'];
    if (data is List) {
      return data.map((e) => InviteDetail.fromJson(e)).toList();
    } else if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .map((e) => InviteDetail.fromJson(e))
          .toList();
    }
    return [];
  }

  Future<bool> redeemGiftCard(String code) async {
    final response = await _post('/user/redeemgiftcard', {
      'giftcard': code,
    }); // _post automatically handles x-www-form-urlencoded
    // Check if data is true or if there's a specific success field
    // User said success response: {"data":true,"type":1,"value":100}
    return response['data'] == true;
  }

  void _logResponse(http.Response response, String url) {
    if (!kDebugMode) return;
    print('[FluxAPI] <-- ${response.statusCode} $url');
    if (response.body.isNotEmpty) {
      print('[FluxAPI] resp: ${response.body}');
    }
  }
}
