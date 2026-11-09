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
import 'widgets/flux_splash.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF05070F),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
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
      title: '队长云',
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
        try { await vpn.disconnect(); } catch (_) {}
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

class FluxApp extends StatelessWidget {
  const FluxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '队长云',
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
  static const _minSplashDuration = 1800;
  
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
        await _api.getUserInfo();
        authResult = true;
        // ✅ 如果已登录，在开屏页面期间预加载数据
        // 这样进入 RootShell 时数据已经准备好了
        if (authResult) {
          try {
            // 预加载核心数据（与 RootShell._initApp 同步）
            await Future.wait([
              RemoteConfigService().getActiveDomain(),
              UserDataService().getNotices(),
            ]);
            debugPrint('[AuthGate] Data preloaded successfully');
          } catch (e) {
            debugPrint('[AuthGate] Preload failed: $e');
            // 预加载失败不影响登录，继续进入主页
          }
        }
      } catch (_) {
        await _config.clearAuth();
        authResult = false;
      }
    }
    
    // 确保动画至少播放 _minSplashDuration 毫秒
    final elapsed = DateTime.now().difference(_startTime).inMilliseconds;
    if (elapsed < _minSplashDuration) {
      await Future.delayed(Duration(milliseconds: _minSplashDuration - elapsed));
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
    // 检查中显示 Flutter 启动动画
    if (_isChecking) {
      return const FluxSplash();
    }
    if (!_authed) {
      return AuthScreen(
        onAuthed: () => setState(() => _authed = true),
      );
    }
    return RootShell(
      onLogout: () => setState(() => _authed = false),
    );
  }
}
