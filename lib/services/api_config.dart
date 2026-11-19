import 'remote_config_service.dart';
import 'secure_store.dart';
import 'subscription_service.dart';
import 'user_data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const _tokenKey = 'api_token';
  static const _authDataKey = 'api_auth_data';

  static String? _tokenCache;
  static String? _authDataCache;

  Future<String> getBaseUrl() async {
    final domain = await RemoteConfigService().getActiveDomain();
    // 移除末尾的斜杠（如果有）
    final cleanDomain = domain.endsWith('/') 
        ? domain.substring(0, domain.length - 1) 
        : domain;
    return '$cleanDomain/api/v1';
  }

  // v1.6.0：token 类字段在 Windows 上用 DPAPI 加密落盘。
  // - 读到「已加密」值 → 解密；
  // - 读到「旧版明文」→ 立即加密回写（自动迁移，用户无感）；
  // - 通道不可用（非 Windows / 未注册）→ 退回明文，绝不阻断、不丢登录态。
  Future<String?> _readSecure(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(key);
    if (stored == null || stored.isEmpty) return null;
    if (SecureStore.isEncrypted(stored)) {
      return await SecureStore.unprotect(stored);
    }
    // 旧明文：迁移为加密（失败则保持明文）
    final encrypted = await SecureStore.protect(stored);
    if (encrypted != null) {
      await prefs.setString(key, encrypted);
    }
    return stored;
  }

  Future<void> _writeSecure(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
      return;
    }
    final encrypted = await SecureStore.protect(value);
    await prefs.setString(key, encrypted ?? value);
  }

  Future<String?> getToken() async {
    final cached = _tokenCache;
    if (cached != null) return cached;
    final value = await _readSecure(_tokenKey);
    _tokenCache = value;
    return value;
  }

  Future<void> setToken(String? token) async {
    _tokenCache = token;
    await _writeSecure(_tokenKey, token);
  }

  Future<String?> getAuthData() async {
    final cached = _authDataCache;
    if (cached != null) return cached;
    final value = await _readSecure(_authDataKey);
    _authDataCache = value;
    return value;
  }

  Future<void> setAuthData(String? value) async {
    _authDataCache = value;
    await _writeSecure(_authDataKey, value);
  }

  Future<void> clearAuth() async {
    _tokenCache = null;
    _authDataCache = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_authDataKey);
    
    // 清除用户数据缓存
    UserDataService().clearCache();
    // 清除订阅缓存（换账号后不会用到上一个账号的线路）
    await SubscriptionService.clearCache();
  }

  Future<void> refreshAuthCache() async {
    _tokenCache = await _readSecure(_tokenKey);
    _authDataCache = await _readSecure(_authDataKey);
  }
}
