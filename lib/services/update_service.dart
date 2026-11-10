import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/dz_ui.dart' show kAppVersion, resolveSiteBase;

/// 一个可下载的新版本
class AppUpdateInfo {
  final String version;
  final int? versionCode;
  final String changelog;
  final bool force;
  final String? minVersion;
  final String apkUrl;
  final String? sha256;
  final int? size;
  final String abi; // arm64-v8a / armeabi-v7a
  final String source; // manifest / github

  /// 当前版本低于 min_version 或 force=true → 不可关闭
  final bool mustUpdate;

  const AppUpdateInfo({
    required this.version,
    required this.changelog,
    required this.force,
    required this.apkUrl,
    required this.abi,
    required this.source,
    required this.mustUpdate,
    this.versionCode,
    this.minVersion,
    this.sha256,
    this.size,
  });
}

/// 下载进度
class UpdateProgress {
  final int received;
  final int? total;
  const UpdateProgress(this.received, this.total);
  double? get fraction =>
      (total == null || total! <= 0) ? null : (received / total!).clamp(0, 1);
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

/// 安装结果
enum InstallResult { started, needPermission, failed }

/// 应用内更新：
/// 1. 版本清单：官网 `/app/version.json`（域名同其他官网链接：远程配置 → 默认），
///    失败回退 GitHub latest release；
/// 2. 启动 / 回前台自动检查（最多每 6 小时一次），「我的 / 关于」可手动检查；
/// 3. 应用内下载到 cache/updates（支持断点续传、已下载的同版本直接复用 —— 官网 /dl 每 IP 每小时限 10 次，
///    所以绝不自动重试），sha256 校验后交给系统安装器（用户需轻点一次「安装」，Android 不允许静默安装）。
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const MethodChannel _ch = MethodChannel('com.example.flux/v2ray');

  static const String manifestPath = '/app/version.json';
  static const String githubLatest =
      'https://api.github.com/repos/bbb555/dzy-app/releases/latest';
  static const Duration autoInterval = Duration(hours: 6);

  static const _kLastCheck = 'update_last_check';
  static const _kSnoozeVer = 'update_snooze_version';
  static const _kSnoozeAt = 'update_snooze_at';
  static const _kForceVer = 'update_force_version';

  /// 最近一次检查发现的新版本（「我的」页可显示小红点 / 新版本号）
  final ValueNotifier<AppUpdateInfo?> available = ValueNotifier(null);

  String get _ua => 'DzyCloud/$kAppVersion (Android)';

  // ───────────────────────── 版本比较 ─────────────────────────
  static List<int> _parts(String v) {
    final core = v
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[-+ ]'))
        .first;
    return core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  /// a<b → 负数；a==b → 0；a>b → 正数
  static int compareVersions(String a, String b) {
    final x = _parts(a), y = _parts(b);
    for (var i = 0; i < 4; i++) {
      final p = i < x.length ? x[i] : 0;
      final q = i < y.length ? y[i] : 0;
      if (p != q) return p.compareTo(q);
    }
    return 0;
  }

  // ───────────────────────── 检查 ─────────────────────────
  /// 检查新版本。[manual]=false 时 6 小时内只查一次。没有新版本返回 null。
  /// 手动检查网络失败会抛 [UpdateException]（界面提示），自动检查失败静默返回 null。
  Future<AppUpdateInfo?> check({bool manual = false}) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final prefs = await SharedPreferences.getInstance();
    if (!manual) {
      final last = prefs.getInt(_kLastCheck);
      // 之前发现过强制更新且仍未更新：不节流，每次启动 / 回前台都提示
      final forcedVer = prefs.getString(_kForceVer);
      final forcedPending =
          forcedVer != null && compareVersions(kAppVersion, forcedVer) < 0;
      if (last != null && !forcedPending) {
        final d = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(last));
        // 6 小时内已检查过：不再请求，也不重复弹窗（「我的」页仍显示新版本号）
        if (!d.isNegative && d < autoInterval) return null;
      }
    }
    await prefs.setInt(_kLastCheck, DateTime.now().millisecondsSinceEpoch);

    final abi = await _preferredAbi();
    AppUpdateInfo? info;
    Object? lastErr;
    try {
      info = await _fromManifest(abi);
    } catch (e) {
      lastErr = e;
      debugPrint('[Update] manifest failed: $e');
    }
    if (info == null) {
      try {
        info = await _fromGithub(abi);
      } catch (e) {
        lastErr = e;
        debugPrint('[Update] github failed: $e');
      }
    }
    if (info == null) {
      if (manual) {
        throw UpdateException(
            lastErr == null ? '暂时无法获取版本信息' : '网络不太顺畅，暂时无法检查更新');
      }
      return null;
    }

    _cleanupOld(keepVersion: info.version);
    final newer = compareVersions(kAppVersion, info.version) < 0;
    available.value = newer ? info : null;
    if (newer && info.mustUpdate) {
      await prefs.setString(_kForceVer, info.version);
    } else {
      await prefs.remove(_kForceVer);
    }
    return newer ? info : null;
  }

  /// 自动检查到的非强制更新：用户点过「稍后」的同一版本 24 小时内不再弹出
  Future<bool> shouldPrompt(AppUpdateInfo info) async {
    if (info.mustUpdate) return true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kSnoozeVer) != info.version) return true;
    final at = prefs.getInt(_kSnoozeAt) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - at >
        const Duration(hours: 24).inMilliseconds;
  }

  Future<void> snooze(AppUpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSnoozeVer, info.version);
    await prefs.setInt(_kSnoozeAt, DateTime.now().millisecondsSinceEpoch);
  }

  Future<String> _preferredAbi() async {
    try {
      final abis =
          await _ch.invokeListMethod<String>('supportedAbis') ?? const [];
      if (abis.contains('arm64-v8a')) return 'arm64-v8a';
      if (abis.any((a) => a.startsWith('armeabi'))) return 'armeabi-v7a';
    } catch (_) {}
    return 'arm64-v8a';
  }

  Future<Map<String, dynamic>> _getJson(String url,
      {Map<String, String>? headers}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      headers?.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateException('HTTP ${res.statusCode}');
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final j = jsonDecode(body);
      if (j is! Map<String, dynamic>) throw const UpdateException('bad json');
      return j;
    } finally {
      client.close(force: true);
    }
  }

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty || s == '…' ? null : s;
  }

  bool _must(String version, bool force, String? minVersion) {
    if (compareVersions(kAppVersion, version) >= 0) return false;
    return force ||
        (minVersion != null && compareVersions(kAppVersion, minVersion) < 0);
  }

  Future<AppUpdateInfo?> _fromManifest(String abi) async {
    final base = await resolveSiteBase();
    final j = await _getJson('$base$manifestPath');
    final version = _str(j['version']);
    if (version == null)
      throw const UpdateException('manifest without version');
    final arm64 = abi == 'arm64-v8a';
    var url = _str(arm64 ? j['apk_arm64'] : j['apk_armv7']);
    var sha = _str(arm64 ? j['sha256_arm64'] : j['sha256_armv7']);
    var size = _int(arm64 ? j['size_arm64'] : j['size_armv7']);
    if (url == null && !arm64) {
      // 没有 32 位包时不要给 32 位设备推 64 位包
      throw const UpdateException('manifest has no armv7 apk');
    }
    if (url == null) throw const UpdateException('manifest has no apk url');
    // 相对路径 → 拼官网域名
    if (url.startsWith('/')) url = '$base$url';
    if (!url.startsWith('https://'))
      throw const UpdateException('apk url must be https');
    if (sha != null && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) sha = null;
    if (size != null && size <= 0) size = null;
    final force = j['force'] == true;
    final minV = _str(j['min_version']);
    return AppUpdateInfo(
      version: version.replaceFirst(RegExp(r'^[vV]'), ''),
      versionCode: _int(j['versionCode']),
      changelog: _str(j['changelog']) ?? '',
      force: force,
      minVersion: minV,
      apkUrl: url,
      sha256: sha?.toLowerCase(),
      size: size,
      abi: abi,
      source: 'manifest',
      mustUpdate: _must(version, force, minV),
    );
  }

  Future<AppUpdateInfo?> _fromGithub(String abi) async {
    final j = await _getJson(githubLatest,
        headers: {'Accept': 'application/vnd.github+json'});
    final tag = _str(j['tag_name']);
    if (tag == null) throw const UpdateException('release without tag');
    final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
    final assets = (j['assets'] as List?) ?? const [];
    Map? asset;
    for (final a in assets) {
      if (a is Map && (a['name'] ?? '').toString().endsWith('-$abi.apk')) {
        asset = a;
        break;
      }
    }
    if (asset == null) throw UpdateException('release has no $abi apk');
    final url = _str(asset['browser_download_url']);
    if (url == null) throw const UpdateException('asset without url');
    String? sha;
    final digest = _str(asset['digest']);
    if (digest != null && digest.startsWith('sha256:')) {
      sha = digest.substring(7).toLowerCase();
    }
    final notes = _str(j['body']) ?? '';
    return AppUpdateInfo(
      version: version,
      changelog: notes,
      force: false,
      apkUrl: url,
      sha256: sha,
      size: _int(asset['size']),
      abi: abi,
      source: 'github',
      mustUpdate: _must(version, false, null),
    );
  }

  // ───────────────────────── 下载 ─────────────────────────
  Future<Directory> _dir() async {
    final tmp = await getTemporaryDirectory(); // Android: context.cacheDir
    final d = Directory('${tmp.path}/updates');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  String _fileName(AppUpdateInfo i) => 'dzy-cloud-${i.version}-${i.abi}.apk';

  /// 删除旧版本安装包（只保留 [keepVersion] 的文件）
  Future<void> _cleanupOld({String? keepVersion}) async {
    try {
      final d = await _dir();
      await for (final f in d.list()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (keepVersion != null &&
            name.startsWith('dzy-cloud-$keepVersion-') &&
            compareVersions(kAppVersion, keepVersion) < 0) {
          continue;
        }
        await f.delete();
      }
    } catch (_) {}
  }

  Future<String?> _sha256(String path) async {
    try {
      return await _ch.invokeMethod<String>('sha256File', {'path': path});
    } catch (e) {
      debugPrint('[Update] sha256 failed: $e');
      return null;
    }
  }

  Future<bool> _verify(AppUpdateInfo info, File f) async {
    final len = await f.length();
    if (info.size != null && len != info.size) return false;
    if (info.sha256 != null) {
      final h = await _sha256(f.path);
      if (h == null) return false;
      return h.toLowerCase() == info.sha256;
    }
    // 没有 sha256 也没有大小时，至少确认是一个 zip（APK）
    if (info.size == null) {
      final raf = await f.open();
      try {
        final head = await raf.read(2);
        return head.length == 2 && head[0] == 0x50 && head[1] == 0x4B;
      } finally {
        await raf.close();
      }
    }
    return true;
  }

  /// 下载并校验。返回校验通过的 APK 文件。一次调用只发起一次下载请求（不自动重试）。
  /// [onVerifying] 进入校验阶段时回调。
  Future<File> download(
    AppUpdateInfo info, {
    required void Function(UpdateProgress p) onProgress,
    VoidCallback? onVerifying,
  }) async {
    final d = await _dir();
    final target = File('${d.path}/${_fileName(info)}');
    final part = File('${target.path}.part');

    // 已下载且校验通过：直接复用，不再占用官网下载次数
    if (await target.exists()) {
      onVerifying?.call();
      if (await _verify(info, target)) return target;
      await target.delete();
    }

    var have = await part.exists() ? await part.length() : 0;
    if (info.size != null && have > info.size!) {
      await part.delete();
      have = 0;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(info.apkUrl));
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.followRedirects = true;
      req.maxRedirects = 5;
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close().timeout(const Duration(seconds: 20));

      if (res.statusCode == 429) {
        await res.drain<void>();
        throw const UpdateException('下载过于频繁，请稍后再试（每小时最多 10 次）');
      }
      if (res.statusCode == 416 && have > 0) {
        // 已经下载完整（服务器无更多内容）
        await res.drain<void>();
      } else {
        final append = res.statusCode == 206 && have > 0;
        if (res.statusCode != 200 && !append) {
          await res.drain<void>();
          throw UpdateException('下载失败（HTTP ${res.statusCode}）');
        }
        if (!append) have = 0;
        int? total = info.size;
        if (total == null && res.contentLength > 0) {
          total = have + res.contentLength;
        }
        sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
        var received = have;
        var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
        onProgress(UpdateProgress(received, total));
        await for (final chunk
            in res.timeout(const Duration(seconds: 30), onTimeout: (s) {
          s.addError(const UpdateException('网络中断，下载已暂停'));
          s.close();
        })) {
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastEmit).inMilliseconds >= 120) {
            lastEmit = now;
            onProgress(UpdateProgress(received, total));
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
        onProgress(UpdateProgress(received, total ?? received));
      }
    } on UpdateException {
      rethrow;
    } on SocketException {
      throw const UpdateException('网络中断，下载已暂停');
    } on TimeoutException {
      throw const UpdateException('网络超时，下载已暂停');
    } on HttpException {
      throw const UpdateException('网络中断，下载已暂停');
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }

    onVerifying?.call();
    if (!await _verify(info, part)) {
      try {
        await part.delete();
      } catch (_) {}
      throw const UpdateException('安装包校验未通过，已删除，请重新下载');
    }
    if (await target.exists()) await target.delete();
    return part.rename(target.path);
  }

  // ───────────────────────── 安装 ─────────────────────────
  Future<bool> canInstall() async {
    try {
      return await _ch.invokeMethod<bool>('canInstallPackages') ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> openInstallSettings() async {
    try {
      await _ch.invokeMethod('openInstallSettings');
    } catch (_) {}
  }

  Future<InstallResult> install(File apk) async {
    try {
      final r =
          await _ch.invokeMethod<String>('installApk', {'path': apk.path});
      switch (r) {
        case 'started':
          return InstallResult.started;
        case 'need_permission':
          return InstallResult.needPermission;
        default:
          return InstallResult.failed;
      }
    } catch (e) {
      debugPrint('[Update] install failed: $e');
      return InstallResult.failed;
    }
  }
}
