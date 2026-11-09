import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:tray_manager/tray_manager.dart';
import 'platform_service.dart';

/// 系统托盘服务 - 桌面端右下角托盘图标
class TrayService with TrayListener {
  static TrayService? _instance;
  static TrayService get instance => _instance ??= TrayService._();
  
  TrayService._();
  
  VoidCallback? onConnect;
  VoidCallback? onDisconnect;
  VoidCallback? onShowWindow;
  VoidCallback? onQuit;
  
  bool _isConnected = false;
  bool _isInitialized = false;
  
  /// 初始化系统托盘
  Future<void> init({
    VoidCallback? onConnect,
    VoidCallback? onDisconnect,
    VoidCallback? onShowWindow,
    VoidCallback? onQuit,
  }) async {
    if (!PlatformService.instance.supportsTray) return;
    
    // 总是更新回调
    this.onConnect = onConnect;
    this.onDisconnect = onDisconnect;
    this.onShowWindow = onShowWindow;
    this.onQuit = onQuit;
    
    if (_isInitialized) {
      await _updateTrayIcon();
      await _updateTrayMenu();
      return;
    }
    
    trayManager.addListener(this);
    
    // 设置托盘图标
    await _updateTrayIcon();
    await _updateTrayMenu();
    
    _isInitialized = true;
  }
  
  /// 更新连接状态
  Future<void> updateConnectionStatus(bool isConnected) async {
    if (!PlatformService.instance.supportsTray) return;
    
    _isConnected = isConnected;
    await _updateTrayIcon(); // 状态改变可能需要改变图标（如果有不同图标）
    await _updateTrayMenu();
  }
  
  /// 更新托盘图标
  Future<void> _updateTrayIcon() async {
    String? iconPath;
    final projectRoot = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // 平台优先级：Linux/ macOS 优先 PNG，Windows 优先 ICO
    final iconNames = Platform.isWindows
        ? ['app_icon.ico', 'app_icon.png']
        : ['app_icon.png', 'app_icon.ico'];

    final candidates = [
      for (final name in iconNames) ...[
        path.join(exeDir, 'data', 'flutter_assets', 'assets', 'icons', name),
        path.join(projectRoot, 'assets', 'icons', name),
        path.join('assets', 'icons', name),
      ]
    ];

    // 调试：打印目录结构
    if (kDebugMode || Platform.isWindows) {
      await _debugListFiles(exeDir);
    }
    
    for (final candidate in candidates) {
       final absPath = path.isAbsolute(candidate) ? candidate : path.absolute(candidate);
       if (await File(absPath).exists()) {
          iconPath = absPath;
          debugPrint('[Tray] Found icon at: $iconPath');
          break;
       }
    }

    if (iconPath == null) {
       debugPrint('[Tray] CRITICAL: No icon file found in any candidate path!');
       debugPrint('[Tray] Candidates were: $candidates');
       // 尝试使用第一个候选路径，即使检测不到 (某些情况下 File.exists 可能不准)
       if (candidates.isNotEmpty) iconPath = candidates.first;
    }

    try {
      debugPrint('[Tray] Setting icon: $iconPath');
      await trayManager.setIcon(iconPath!);
      // Windows 上有时需要再次设置以确保显示，尤其是在刚启动时
      if (Platform.isWindows) {
        Future.delayed(const Duration(milliseconds: 1000), () {
           trayManager.setIcon(iconPath!);
        });
      }
    } catch (e) {
      debugPrint('[Tray] Set icon error: $e');
    }
    
    // setToolTip 在 Linux 上可能不支持，单独捕获异常
    try {
      await trayManager.setToolTip('队长云 - ${_isConnected ? "Connected" : "Disconnected"}');
    } catch (e) {
      // Linux 上 setToolTip 未实现，忽略此错误
      debugPrint('[Tray] setToolTip not supported on this platform');
    }
  }

  Future<void> _debugListFiles(String dirPath, {String prefix = '', int depth = 0}) async {
    if (depth > 4) return; // 防止递归太深
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;
      
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory) {
           print('[TypesDebug] ${prefix}D: ${path.basename(entity.path)}');
           if (path.basename(entity.path) == 'data' || 
               path.basename(entity.path) == 'flutter_assets' || 
               path.basename(entity.path) == 'assets' || 
               path.basename(entity.path) == 'icons') {
             await _debugListFiles(entity.path, prefix: '$prefix  ', depth: depth + 1);
           }
        } else {
           if (path.extension(entity.path) == '.ico' || path.extension(entity.path) == '.png') {
              print('[TypesDebug] ${prefix}F: ${path.basename(entity.path)} (${entity.path})');
           }
        }
      }
    } catch (e) {
      print('[TypesDebug] Error listing $dirPath: $e');
    }
  }
  
  /// 更新托盘菜单
  Future<void> _updateTrayMenu() async {
    final menu = Menu(
      items: [
        MenuItem(
          key: 'show',
          label: '显示主窗口',
        ),
        MenuItem.separator(),
        MenuItem(
          key: _isConnected ? 'disconnect' : 'connect',
          label: _isConnected ? '断开连接' : '快速连接',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: '退出',
        ),
      ],
    );
    
    await trayManager.setContextMenu(menu);
  }
  
  @override
  void onTrayIconMouseDown() {
    // 单击显示窗口
    onShowWindow?.call();
  }
  
  @override
  void onTrayIconRightMouseDown() {
    // 右键显示菜单
    trayManager.popUpContextMenu();
  }
  
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        onShowWindow?.call();
        break;
      case 'connect':
        onConnect?.call();
        break;
      case 'disconnect':
        onDisconnect?.call();
        break;
      case 'quit':
        onQuit?.call();
        break;
    }
  }
  
  /// 释放资源
  void dispose() {
    if (_isInitialized) {
      trayManager.removeListener(this);
      trayManager.destroy();
      _isInitialized = false;
    }
  }
}
