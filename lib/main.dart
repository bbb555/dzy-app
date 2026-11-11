import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/generated/app_localizations.dart';
import 'screens/auth_screen.dart';
import 'screens/root_shell.dart';
import 'services/api_config.dart';
import 'services/remote_config_service.dart';
import 'services/tray_service.dart';
import 'services/unified_vpn_service.dart';
import 'services/user_data_service.dart';
import 'services/v2board_api.dart';
import 'services/v2ray_service.dart';
import 'theme/app_theme.dart';
import 'utils/asset_utils.dart';
import 'widgets/animated_background.dart';
import 'widgets/flux_splash.dart';
import 'theme/app_colors.dart';

/// 全局系统栏样式：深色背景 + 浅色图标，导航栏透明且不加系统对比度遮罩
const SystemUiOverlayStyle kDzOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

void main() {
  // v1.3.0 加固：Release 包不向 logcat 输出任何 Dart 日志（print / debugPrint），
  // 避免订阅地址、节点信息、接口返回等通过 `adb logcat` 泄露。
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
    runZoned(_main,
        zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {}));
  } else {
    _main();
  }
}

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 沉浸式：状态栏 / 导航栏透明，由全局深色背景一直铺到屏幕边缘，
  // 避免底部系统导航栏与页面暗角颜色不一致出现色带。
  if (!kIsWeb && Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  SystemChrome.setSystemUIOverlayStyle(kDzOverlayStyle);
  await _registerExitCleanup();

  // Load persisted TUN mode state
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await V2rayService().loadTunState();
  }

  // 初始化资源文件（复制 geoip.dat/geosite.dat 到文件目录）
  if (!kIsWeb && Platform.isAndroid) {
    // 只有 Android 需要手动复制到 filesDir 给 native 层使用
    // Desktop 端直接通过 Process 运行二进制，二进制会自动找同级目录的 dat
    // 或者我们在 desktop_proxy_service 已经处理了
    await AssetUtils.copyAssets();
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    // 初始化托盘 (确保图标尽早显示)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await TrayService.instance.init(
          onShowWindow: () async {
            await windowManager.show();
            await windowManager.focus();
          },
        );
      } catch (e) {
        debugPrint('[Main] Tray init error: $e');
      }
    }

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1000, 720),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: '队长云加速',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();

      // 设置窗口图标
      try {
        if (Platform.isLinux || Platform.isWindows) {
          final exePath = Platform.resolvedExecutable;
          final exeDir = File(exePath).parent.path;
          final assetPath = Platform.isWindows
              ? 'assets/icons/app_icon.ico'
              : 'assets/icons/app_icon.png';

          // 尝试构建后的路径
          String iconPath = '$exeDir/data/flutter_assets/$assetPath';
          if (!await File(iconPath).exists()) {
            // 开发环境回退
            iconPath = assetPath;
          }

          if (await File(iconPath).exists()) {
            await windowManager.setIcon(iconPath);
          }
        }
      } catch (e) {
        debugPrint('[Main] Error setting icon: $e');
      }
    });
  }

  runApp(const FluxApp());
}

Future<void> _registerExitCleanup() async {
  if (kIsWeb) return;
  final vpn = UnifiedVpnService.instance;

  // Windows: 使用 WindowListener 监听窗口关闭事件
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    windowManager.addListener(_AppCloseListener(vpn));
  }

  // Unix: 捕获退出信号
  if (!Platform.isWindows) {
    for (final sig in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      sig.watch().listen((_) async {
        try {
          await vpn.disconnect();
        } catch (_) {}
        exit(0);
      });
    }
  }
}

/// 监听窗口关闭事件，确保清理 TUN 和代理进程
class _AppCloseListener extends WindowListener {
  final UnifiedVpnService vpn;
  _AppCloseListener(this.vpn);

  @override
  void onWindowClose() async {
    debugPrint('[AppCloseListener] Window closing, cleaning up...');
    try {
      await vpn.disconnect();
      debugPrint('[AppCloseListener] VPN disconnected');
    } catch (e) {
      debugPrint('[AppCloseListener] Disconnect error: $e');
    }

    // 强制清理 sing-box 进程（TUN 网卡由 sing-box 自动清理）
    if (Platform.isWindows) {
      try {
        await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
      } catch (_) {}
    }

    await windowManager.destroy();
  }
}

/// 全局外壳：
/// 1. 唯一的动态背景 —— 放在 Navigator 之外，任何页面切换、Tab 切换、启动→登录→首页
///    都只动内容，背景始终是同一个实例、同一相位，不闪、不跳、不露黑底；
/// 2. 系统栏样式固定；
/// 3. 限制系统超大字体的缩放上限（1.3x），避免固定尺寸控件内文字被裁切。
Widget dzAppBuilder(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(
      textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3),
    ),
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: kDzOverlayStyle,
      child: ColoredBox(
        color: AppColors.background,
        child: AnimatedMeshBackground(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
}

class FluxApp extends StatelessWidget {
  const FluxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '队长云加速',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      // 多语言配置
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: dzAppBuilder,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _api = V2BoardApi();
  final _config = ApiConfig();
  bool _authed = false;
  bool _isChecking = true;
  final _startTime = DateTime.now();

  // 最小启动动画时间（毫秒）- 让动画至少播放这么久
  static const _minSplashDuration = 1200;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await _config.refreshAuthCache();
    final token = await _config.getToken();
    final authData = await _config.getAuthData();

    bool authResult = false;

    if (token == null && authData == null) {
      authResult = false;
    } else {
      try {
        await _api.getUserInfo().timeout(const Duration(seconds: 8));
        authResult = true;
      } on V2BoardApiException catch (e) {
        // 只有服务器明确表示登录失效（401 / 403）才清除登录；
        // 5xx 等服务器异常不应把用户踢回登录页
        if (e.statusCode == 401 || e.statusCode == 403) {
          await _config.clearAuth();
          authResult = false;
        } else {
          authResult = true;
        }
      } catch (_) {
        // 断网 / 超时：保留登录，离线进入（订阅缓存仍可连接），不再清除登录信息
        authResult = true;
      }
      if (authResult) {
        // 预热（不阻塞开屏）：域名、公告
        RemoteConfigService()
            .getActiveDomain()
            .then((_) => UserDataService().getNotices())
            .then((_) {}, onError: (_) {});
      }
    }

    // 确保动画至少播放 _minSplashDuration 毫秒
    final elapsed = DateTime.now().difference(_startTime).inMilliseconds;
    if (elapsed < _minSplashDuration) {
      await Future.delayed(
          Duration(milliseconds: _minSplashDuration - elapsed));
    }

    if (mounted) {
      setState(() {
        _authed = authResult;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 启动动画 → 登录 → 首页：交叉淡入，背景由全局外壳提供，保持静止
    final Widget page;
    if (_isChecking) {
      page = const FluxSplash(key: ValueKey('splash'));
    } else if (!_authed) {
      page = AuthScreen(
        key: const ValueKey('auth'),
        onAuthed: () => setState(() => _authed = true),
      );
    } else {
      page = RootShell(
        key: const ValueKey('shell'),
        onLogout: () => setState(() => _authed = false),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: page,
    );
  }
}
