import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// v1.6.0 电脑端安全加固 —— 落盘敏感字段的 Windows DPAPI 加密。
///
/// 配合 C++ 侧的 MethodChannel（`com.dzy.cloud/secure_store`，见 windows/runner/
/// secure_store.cpp）：用 Windows 自带的 DPAPI 按**当前登录用户**加解密，密文换机 /
/// 换用户即无法解开。不引第三方依赖。
///
/// 存储格式：`dpapi:v1:<base64(密文)>`；不带该前缀的值一律按**旧版明文**处理。
///
/// 降级策略（绝不阻断启动、不丢登录态）：
/// - 非 Windows、通道未注册（MissingPluginException）、加解密失败 —— [protect] 返回
///   null，调用方退回明文落盘；[unprotect] 返回 null。
class SecureStore {
  SecureStore._();

  static const MethodChannel _channel =
      MethodChannel('com.dzy.cloud/secure_store');

  /// 加密值的标记前缀
  static const String prefix = 'dpapi:v1:';

  static bool? _available;
  static bool _disabled = false; // 通道缺失（例如开发机上没跑 C++ runner）
  static Future<bool>? _probing;

  /// 值是否已被加密（带标记前缀）
  static bool isEncrypted(String value) => value.startsWith(prefix);

  /// 通道是否可用（懒探测一次）
  static Future<bool> get available {
    if (_disabled) return Future.value(false);
    final cached = _available;
    if (cached != null) return Future.value(cached);
    return _probing ??= _probe();
  }

  static Future<bool> _probe() async {
    try {
      if (kIsWeb || !Platform.isWindows) {
        _disabled = true;
        return false;
      }
      final ok = await _channel.invokeMethod<bool>('available');
      _available = ok == true;
      return _available!;
    } on MissingPluginException {
      _disabled = true;
      return false;
    } catch (e) {
      // 其它错误：本次不可用，但不永久禁用（下次可重试）
      debugPrint('[SecureStore] probe failed: $e');
      return false;
    } finally {
      _probing = null;
    }
  }

  /// 明文 → `dpapi:v1:<base64>`。不可用或失败返回 null（调用方退回明文）。
  static Future<String?> protect(String plain) async {
    if (plain.isEmpty) return null;
    if (!await available) return null;
    try {
      final b64 = await _channel.invokeMethod<String>('protect', plain);
      if (b64 == null || b64.isEmpty) return null;
      return '$prefix$b64';
    } catch (e) {
      debugPrint('[SecureStore] protect failed: $e');
      return null;
    }
  }

  /// 存储值 → 明文。非加密值原样返回；解密失败返回 null。
  static Future<String?> unprotect(String stored) async {
    if (!isEncrypted(stored)) return stored;
    if (!await available) return null;
    try {
      return await _channel
          .invokeMethod<String>('unprotect', stored.substring(prefix.length));
    } catch (e) {
      debugPrint('[SecureStore] unprotect failed: $e');
      return null;
    }
  }
}
