import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.6.0 电脑端安全加固 —— 稳定设备标识。
///
/// 目标：为每台电脑生成一个**稳定且不随重装 / 换账号改变**的设备 ID，并让它出现在
/// 所有发往服务端的请求头 `X-Device-Id` 中，供服务端做设备风控 / 线路绑定。
///
/// 取值优先级：
/// 1. Windows 注册表 `HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid`（系统安装时生成，
///    稳定、不随用户 / 应用改动）；
/// 2. 取不到（权限被拒 / 非 Windows）时，退化为随机 UUID v4 并持久化到 SharedPreferences，
///    以后固定复用；
/// 3. 任何一步失败都不抛异常、不阻断启动 —— 最坏情况下返回一个「本次进程内」的临时 UUID。
///
/// 不引第三方依赖：UUID v4 由 [Random.secure] 现场生成。
class DeviceId {
  DeviceId._();

  /// 请求头字段名（服务端约定）
  static const String headerName = 'X-Device-Id';

  /// SharedPreferences 中持久化 UUID 的键
  static const String _prefsKey = 'device_id';

  /// 解析失败时返回兜底值，绝不为空
  static const String _fallback = 'unknown-device';

  static String? _cache;
  static Future<String>? _inflight;

  /// 取设备 ID（带内存缓存，进程内只解析一次）。
  static Future<String> get() {
    final cached = _cache;
    if (cached != null && cached.isNotEmpty) return Future.value(cached);
    return _inflight ??= _resolve().then((id) {
      _cache = id;
      _inflight = null;
      return id;
    }).catchError((Object e) {
      _inflight = null;
      _cache = _fallback;
      debugPrint('[DeviceId] resolve failed: $e');
      return _fallback;
    });
  }

  /// 便捷方法：返回可直接合并进请求头的 Map。
  static Future<Map<String, String>> header() async =>
      {headerName: await get()};

  /// 同步读取已缓存的 ID（未解析过时返回 null）。
  static String? get cached => _cache;

  static Future<String> _resolve() async {
    // 1. Windows：优先读注册表 MachineGuid
    if (!kIsWeb && Platform.isWindows) {
      final guid = await _readWindowsMachineGuid();
      if (guid != null && guid.isNotEmpty) return guid;
    }

    // 2. 退化：持久化的随机 UUID
    final persisted = await _readPersisted();
    if (persisted != null && persisted.isNotEmpty) return persisted;

    // 3. 首次运行：生成并持久化
    final generated = _uuidV4();
    await _persist(generated);
    return generated;
  }

  /// 读取 `HKLM\SOFTWARE\Microsoft\Cryptography` 的 `MachineGuid`。
  /// 失败（无权限 / 命令不存在 / 解析失败）返回 null，交由上层退化处理。
  static Future<String?> _readWindowsMachineGuid() async {
    try {
      final result = await Process.run(
        'reg',
        ['query', r'HKLM\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid'],
        runInShell: true,
      ).timeout(const Duration(seconds: 5));
      final out = '${result.stdout}';
      // 输出形如：
      //   ...\Cryptography
      //       MachineGuid    REG_SZ    9a1b...-...
      for (final line in out.split('\n')) {
        final idx = line.indexOf('MachineGuid');
        if (idx < 0) continue;
        final parts = line.substring(idx + 'MachineGuid'.length).trim().split(RegExp(r'\s+'));
        // parts = ['REG_SZ', '<guid>']
        for (final p in parts) {
          final v = p.trim();
          if (v.length >= 8 && RegExp(r'^[0-9a-fA-F\-]+$').hasMatch(v)) {
            return v;
          }
        }
      }
    } catch (e) {
      debugPrint('[DeviceId] MachineGuid read failed: $e');
    }
    return null;
  }

  static Future<String?> _readPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persist(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, id);
    } catch (_) {
      // 落盘失败不影响本次使用
    }
  }

  /// 生成 RFC4122 v4 UUID（不依赖第三方包）。
  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-'
        '${h(4)}${h(5)}-'
        '${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-'
        '${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}
