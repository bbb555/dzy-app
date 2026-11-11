import 'dart:io';

import 'package:flutter/material.dart';

import '../services/traffic_speed_service.dart' show formatBytes;
import '../services/update_service.dart';
import '../theme/app_colors.dart';
import 'dz_ui.dart';

/// 弹出新版本对话框。force / 低于 min_version 时不可关闭。
Future<void> showUpdateDialog(BuildContext context, AppUpdateInfo info) {
  return showDzDialog<void>(
    context,
    dismissible: !info.mustUpdate,
    builder: (_) => UpdateDialog(info: info),
  );
}

/// 手动检查更新（「我的」/「关于」）：有新版本弹窗，否则轻提示
Future<void> manualCheckUpdate(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
      const SnackBar(content: Text('正在检查更新…'), duration: Duration(seconds: 2)));
  try {
    final info = await UpdateService.instance.check(manual: true);
    messenger?.hideCurrentSnackBar();
    if (!context.mounted) return;
    if (info == null) {
      messenger?.showSnackBar(SnackBar(
          content: Text('已是最新版本 v$kAppVersion'),
          duration: const Duration(seconds: 2)));
      return;
    }
    await showUpdateDialog(context, info);
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
        content: Text(e is UpdateException ? e.message : '暂时无法检查更新，请稍后再试'),
        duration: const Duration(seconds: 3)));
  }
}

enum UpdateStage {
  ready,
  downloading,
  verifying,
  permission,
  installing,
  error
}

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;

  /// 仅用于界面预览
  @visibleForTesting
  final UpdateStage? previewStage;
  @visibleForTesting
  final UpdateProgress? previewProgress;

  const UpdateDialog({
    super.key,
    required this.info,
    this.previewStage,
    this.previewProgress,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog>
    with WidgetsBindingObserver {
  final _svc = UpdateService.instance;
  late UpdateStage _stage = widget.previewStage ?? UpdateStage.ready;
  UpdateProgress? _progress;
  String? _error;
  File? _apk;
  bool _waitingPermission = false;

  AppUpdateInfo get info => widget.info;

  @override
  void initState() {
    super.initState();
    _progress = widget.previewProgress;
    WidgetsBinding.instance.addObserver(this);
    // 之前选了「后台继续下载」又重新打开：直接接回进行中的下载并显示进度
    if (widget.previewStage == null && _svc.isDownloading(info)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从「允许安装未知应用」设置页返回后自动继续安装
    if (state == AppLifecycleState.resumed && _waitingPermission) {
      _waitingPermission = false;
      _install();
    }
  }

  Future<void> _start() async {
    if (_stage == UpdateStage.downloading || _stage == UpdateStage.verifying) {
      return;
    }
    setState(() {
      _stage = UpdateStage.downloading;
      _error = null;
      _progress = UpdateProgress(0, info.size);
    });
    try {
      final f = await _svc.download(
        info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onVerifying: () {
          if (mounted) setState(() => _stage = UpdateStage.verifying);
        },
      );
      _apk = f;
      await _install();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = UpdateStage.error;
        _error = e is UpdateException ? e.message : '下载失败，请检查网络后重试';
      });
    }
  }

  Future<void> _install() async {
    final f = _apk;
    if (f == null) return;
    final r = await _svc.install(f);
    if (!mounted) return;
    setState(() {
      switch (r) {
        case InstallResult.started:
          _stage = UpdateStage.installing;
        case InstallResult.needPermission:
          _stage = UpdateStage.permission;
        case InstallResult.failed:
          _stage = UpdateStage.error;
          _error = '无法打开系统安装界面，可改用浏览器下载安装';
      }
    });
  }

  Future<void> _grant() async {
    _waitingPermission = true;
    await _svc.openInstallSettings();
  }

  Future<void> _later() async {
    await _svc.snooze(info);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final must = info.mustUpdate;
    return PopScope(
      canPop: !must,
      child: DzDialog(
        title: must ? '请更新到最新版本' : '发现新版本',
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.goldGradient,
            boxShadow: [
              BoxShadow(
                  color: AppColors.goldMid.withValues(alpha: 0.45),
                  blurRadius: 22,
                  spreadRadius: -4),
            ],
          ),
          child: const Icon(Icons.rocket_launch_rounded,
              color: AppColors.onGold, size: 26),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _versionRow(),
            const SizedBox(height: 14),
            if (info.changelog.trim().isNotEmpty) _changelog(),
            if (must) ...[
              const SizedBox(height: 10),
              Text('当前版本已停止支持，更新后即可继续使用',
                  textAlign: TextAlign.center,
                  style: DzText.caption.copyWith(color: AppColors.warning)),
            ],
            AnimatedSize(
              duration: DzMotion.base,
              curve: DzMotion.ease,
              child: _statusArea(),
            ),
          ],
        ),
        actions: _actions(must),
      ),
    );
  }

  Widget _versionRow() {
    Widget chip(String t, {bool gold = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: gold ? AppColors.goldGradient : null,
            color: gold ? null : Colors.white.withValues(alpha: 0.05),
            border: gold ? null : Border.all(color: AppColors.border),
          ),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: gold ? AppColors.onGold : AppColors.textSecondary)),
        );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            chip('v$kAppVersion'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 16, color: AppColors.gold),
            ),
            chip('v${info.version}', gold: true),
          ],
        ),
        if (info.size != null) ...[
          const SizedBox(height: 8),
          Text(
              '安装包 ${formatBytes(info.size!)} · ${info.abi == 'arm64-v8a' ? '64 位' : '32 位'}',
              style: DzText.caption.copyWith(fontSize: 11)),
        ],
      ],
    );
  }

  Widget _changelog() {
    final lines = info.changelog
        .replaceAll('\r', '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 168),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DzRadius.md),
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: AppColors.border),
      ),
      child: ShaderMask(
        // 底部渐隐：内容可滚动时不出现被硬切的半行字
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.86, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('更新内容',
                  style: DzText.overline.copyWith(color: AppColors.gold)),
              const SizedBox(height: 8),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 7, right: 8),
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: AppColors.goldDeep),
                      ),
                      Expanded(
                        child: Text(l.replaceFirst(RegExp(r'^[-*•·]\s*'), ''),
                            style: DzText.body
                                .copyWith(fontSize: 13, height: 1.5)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusArea() {
    switch (_stage) {
      case UpdateStage.ready:
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
              '${info.sha256 != null ? '安装包经 SHA-256 校验 · ' : ''}下载后系统会请你轻点一次「安装」',
              textAlign: TextAlign.center,
              style: DzText.caption.copyWith(fontSize: 11)),
        );
      case UpdateStage.downloading:
      case UpdateStage.verifying:
        final p = _progress;
        final frac = p?.fraction;
        final verifying = _stage == UpdateStage.verifying;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Bar(value: verifying ? 1 : frac),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    verifying
                        ? '正在校验安装包…'
                        : p == null
                            ? '正在连接…'
                            : p.total != null
                                ? '${formatBytes(p.received)} / ${formatBytes(p.total!)}'
                                : '已下载 ${formatBytes(p.received)}',
                    style: DzText.caption.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  const Spacer(),
                  if (!verifying && frac != null)
                    Text('${(frac * 100).floor()}%',
                        style: DzText.metricSmall
                            .copyWith(color: AppColors.gold, fontSize: 13)),
                ],
              ),
            ],
          ),
        );
      case UpdateStage.permission:
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _notice(
            Icons.verified_user_rounded,
            '还差一步：允许安装',
            '为了安全，Android 需要你允许「队长云加速」安装应用。点下方按钮，在系统页面打开「允许来自此来源的应用」，返回后将自动继续安装。',
          ),
        );
      case UpdateStage.installing:
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _notice(
            Icons.touch_app_rounded,
            '已打开系统安装界面',
            '请在系统弹窗中轻点「安装」完成更新（Android 不支持静默安装）。账号与设置会完整保留。',
          ),
        );
      case UpdateStage.error:
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _notice(
              Icons.error_outline_rounded, '更新未完成', _error ?? '下载失败，请检查网络后重试',
              danger: true),
        );
    }
  }

  Widget _notice(IconData icon, String title, String body,
      {bool danger = false}) {
    final c = danger ? AppColors.danger : AppColors.gold;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DzRadius.md),
        color: c.withValues(alpha: 0.07),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: DzText.headline.copyWith(fontSize: 14, color: c)),
                const SizedBox(height: 4),
                Text(body,
                    style: DzText.caption.copyWith(
                        height: 1.55, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(bool must) {
    final later = must ? null : GhostButton(label: '稍后再说', onPressed: _later);
    switch (_stage) {
      case UpdateStage.ready:
        return [
          GoldButton(
              label: '立即更新',
              icon: Icons.download_rounded,
              height: 50,
              onPressed: _start),
          if (later != null) ...[const SizedBox(height: 10), later],
        ];
      case UpdateStage.downloading:
      case UpdateStage.verifying:
        // 下载中不提供重复点击的入口（官网 /dl 每 IP 每小时限 10 次）
        return [
          if (!must)
            GhostButton(
                label: '后台继续下载',
                onPressed: () => Navigator.of(context).maybePop()),
        ];
      case UpdateStage.permission:
        return [
          GoldButton(
              label: '去开启「允许安装」',
              icon: Icons.settings_rounded,
              height: 50,
              onPressed: _grant),
          const SizedBox(height: 10),
          GhostButton(label: '我已开启，继续安装', onPressed: _install),
        ];
      case UpdateStage.installing:
        return [
          GoldButton(
              label: '重新打开安装界面',
              icon: Icons.install_mobile_rounded,
              height: 50,
              onPressed: _install),
          if (later != null) ...[const SizedBox(height: 10), later],
        ];
      case UpdateStage.error:
        return [
          GoldButton(
              label: '重新下载',
              icon: Icons.refresh_rounded,
              height: 50,
              onPressed: _start),
          const SizedBox(height: 10),
          GhostButton(
              label: '用浏览器下载',
              icon: Icons.open_in_new_rounded,
              onPressed: () => openSite(SiteLinks.download, context)),
          if (later != null) ...[const SizedBox(height: 10), later],
        ];
    }
  }
}

/// 金色下载进度条（value 为 null 时为流动的不确定进度）
class _Bar extends StatelessWidget {
  final double? value;
  const _Bar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: value == null
            ? const LinearProgressIndicator(
                color: AppColors.gold, backgroundColor: Color(0x14FFFFFF))
            : TweenAnimationBuilder<double>(
                tween: Tween(end: value!.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 220),
                builder: (_, v, __) => Stack(
                  children: [
                    Container(color: Colors.white.withValues(alpha: 0.07)),
                    FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.goldGradient,
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.goldMid.withValues(alpha: 0.6),
                                blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
