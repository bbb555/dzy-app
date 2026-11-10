import 'remote_config_service.dart';
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

  Future<String?> getToken() async {
    final cached = _tokenCache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_tokenKey);
    _tokenCache = value;
    return value;
  }

  Future<void> setToken(String? token) async {
    _tokenCache = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_tokenKey);
      return;
    }
    await prefs.setString(_tokenKey, token);
  }

  Future<String?> getAuthData() async {
    final cached = _authDataCache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_authDataKey);
    _authDataCache = value;
    return value;
  }

  Future<void> setAuthData(String? value) async {
    _authDataCache = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_authDataKey);
      return;
    }
    await prefs.setString(_authDataKey, value);
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
    final prefs = await SharedPreferences.getInstance();
    _tokenCache = prefs.getString(_tokenKey);
    _authDataCache = prefs.getString(_authDataKey);
  }
}
