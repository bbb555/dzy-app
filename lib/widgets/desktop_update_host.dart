import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';

import '../services/update_service.dart';
import 'dz_ui.dart' show kAppVersion;
import 'update_dialog.dart';

/// 全局 navigator：电脑端的自动更新检查由 [DesktopUpdateHost] 在页面之外发起
/// （Windows 上 RootShell 不检查更新，也不该为一个提示去改首页），
/// 需要一个不依赖某个页面 build 上下文的入口来弹更新对话框。
final GlobalKey<NavigatorState> dzNavigatorKey = GlobalKey<NavigatorState>();

/// 电脑端（Windows）更新提示宿主：
/// * 启动后检查一次；
/// * 回到前台再检查一次（是否真的请求由 UpdateService.check 自己按 6 小时节流决定）；
/// * 发现新版本 → 弹更新对话框：
///   - 非强制更新：点过「稍后再说」后 24 小时内不再自动弹（与安卓一致）；
///   - 强制更新（清单 force=true 或当前版本低于 min_version）：每次启动/回前台都提示，弹窗不可关闭。
class DesktopUpdateHost with WidgetsBindingObserver {
  DesktopUpdateHost._();
  static final DesktopUpdateHost instance = DesktopUpdateHost._();

  bool _started = false;
  bool _checking = false;

  /// 只在 Windows 生效（安卓仍由 RootShell 自动检查）。在 runApp 之后调用一次。
  void start() {
    if (_started || kIsWeb || !Platform.isWindows) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
    debugPrint('[Update] desktop update checker started (current=$kAppVersion)');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final info = await UpdateService.instance.check();
      if (info == null) return;
      if (!info.mustUpdate && !await UpdateService.instance.shouldPrompt(info)) {
        debugPrint('[Update] ${info.version} 已提示过，本次跳过');
        return;
      }
      final ctx = await _dialogContext();
      if (ctx == null) {
        debugPrint('[Update] 没有可用的 Navigator，跳过本次提示');
        return;
      }
      await showUpdateDialog(ctx, info);
      // 点遮罩关闭也算「稍后」：同一版本 24 小时内不再自动弹出
      if (!info.mustUpdate) await UpdateService.instance.snooze(info);
    } catch (e) {
      // 更新检查/提示失败绝不能影响主流程（登录、连接）
      debugPrint('[Update] desktop check failed: $e');
    } finally {
      _checking = false;
    }
  }

  /// 等 Navigator 就绪（启动瞬间可能还在启动页/登录页，或对话框需要 Overlay）
  Future<BuildContext?> _dialogContext() async {
    for (var i = 0; i < 12; i++) {
      final ctx = dzNavigatorKey.currentState?.overlay?.context;
      if (ctx != null && ctx.mounted) return ctx;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }
}
