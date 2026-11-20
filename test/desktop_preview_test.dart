// 电脑端（Windows）首页「真实渲染」预览图
//
// 只在 Windows 上跑（本地没有 Flutter SDK 的开发机不用管，CI 的 windows.yml 会跑）：
//   flutter test --update-goldens test/desktop_preview_test.dart
// 产物：test/goldens/desktop_home_*.png，CI 里作为 artifact 上传。
//
// 字体：Windows 端界面用微软雅黑（DzDesk.cjkFont），测试环境里手动把系统字体注册成
// 'Microsoft YaHei' / 'Roboto'，否则中文会渲染成方块。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/models/server_node.dart';
import 'package:flux/screens/desktop_home.dart';
import 'package:flux/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Size _deskSize = Size(1440, 900);

Future<bool> _registerFont(String path, List<String> families) async {
  final file = File(path);
  if (!file.existsSync()) return false;
  final bytes = await file.readAsBytes();
  for (final family in families) {
    try {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    } catch (_) {/* .ttc 集合字体可能加载失败，换下一个 */}
  }
  return true;
}

Future<void> _loadCjkFont() async {
  const families = ['Microsoft YaHei', 'Roboto'];
  final candidates = <String>[
    // 仓库里若有自带字体优先（1.5.8 时期的预览图就用它）
    'assets/fonts/NotoSansSC-Regular.otf',
    // Windows 系统字体：黑体是单体 ttf，最稳；雅黑是 ttc 集合
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\msyh.ttc',
    r'C:\Windows\Fonts\msyh.ttf',
    r'C:\Windows\Fonts\msyhbd.ttc',
    r'C:\Windows\Fonts\Deng.ttf',
  ];
  for (final path in candidates) {
    if (await _registerFont(path, families)) return;
  }
}

List<ServerNode> _previewNodes() => [
      ServerNode(
        name: '🇭🇰 香港 01 · 智能优选',
        address: 'hk01.edge.dzy.cloud',
        port: 443,
        protocol: 'vless',
        latency: 38,
        bandwidthMbps: 1000,
        isSelected: true,
      ),
      ServerNode(
        name: '🇯🇵 日本 大阪 02',
        address: 'osaka02.edge.dzy.cloud',
        port: 443,
        protocol: 'trojan',
        latency: 62,
        bandwidthMbps: 500,
      ),
      ServerNode(
        name: '🇸🇬 新加坡 03',
        address: 'sg03.edge.dzy.cloud',
        port: 443,
        protocol: 'vmess',
        latency: 88,
        bandwidthMbps: 300,
      ),
      ServerNode(
        name: '🇺🇸 美国 洛杉矶 04',
        address: 'la04.edge.dzy.cloud',
        port: 443,
        protocol: 'vless',
        latency: 143,
      ),
    ];

/// 近 7 日加速秒数（旧 → 新，最后一项是今天）
const List<int> _week = [1800, 4200, 2400, 6600, 3000, 5460, 3600];

Widget _wrap(Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    // 真机上 DesktopHome 是由 root_shell 的 Scaffold 包着的（Scaffold 自带 Material）。
    // 预览要还原这一层：否则里面的 InkWell/InkResponse 找不到 Material 祖先会抛
    // "No Material widget found"，golden 里会出现一块红色报错块（曾真的出现过）。
    home: Material(
      type: MaterialType.transparency,
      child: home,
    ),
  );
}

DesktopHome _home({
  required bool connected,
  bool busy = false,
  bool failed = false,
  String? notice,
  Duration session = Duration.zero,
  List<ServerNode>? nodes,
}) {
  return DesktopHome(
    onConnectPressed: () {},
    isConnected: connected,
    isConnecting: busy,
    isError: failed,
    statusMessage: connected ? '已连接 · 香港 01 · 38ms' : (busy ? '正在建立隧道…' : ''),
    nodeName: connected ? '🇭🇰 香港 01 · 智能优选' : null,
    nodeLatency: connected ? 38 : null,
    liveLatency: connected ? 34 : null,
    nodeBandwidth: connected ? 1000 : null,
    nodeProtocol: connected ? 'vless' : null,
    autoMode: true,
    preview: DesktopPreview(
      nodes: nodes ?? _previewNodes(),
      weekSeconds: _week,
      email: '13800008888@qq.com',
      daysLeft: null,
      planName: '时长会员',
      notice: notice,
      session: session,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _loadCjkFont();
  });

  Future<void> snap(WidgetTester tester, Widget widget, String name,
      {Size size = _deskSize}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_wrap(widget));
    // 光环是循环动画，不能 pumpAndSettle；固定推进到同一个相位保证可重复
    await tester.pump(const Duration(milliseconds: 900));
    await expectLater(
      find.byType(DesktopHome),
      matchesGoldenFile('goldens/$name.png'),
    );
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('电脑端首页预览：已连接', (tester) async {
    if (!Platform.isWindows) return; // 非 Windows 平台跳过（字体/排版不同）
    await snap(
      tester,
      _home(
        connected: true,
        session: const Duration(hours: 1, minutes: 26, seconds: 12),
        notice: '节点线路已升级至 IEPL 专线，晚高峰更稳',
      ),
      'desktop_home_connected',
    );
  });

  testWidgets('电脑端首页预览：未连接', (tester) async {
    if (!Platform.isWindows) return;
    await snap(tester, _home(connected: false), 'desktop_home_idle');
  });

  testWidgets('电脑端首页预览：连接中', (tester) async {
    if (!Platform.isWindows) return;
    await snap(
      tester,
      _home(connected: false, busy: true),
      'desktop_home_connecting',
    );
  });

  // 1.0.1 的默认开窗就是 1000x720，用户报「打开就重叠」正是在这个尺寸。
  // 单独出一版真实渲染图，专门盯这个问题，改动回归一眼能看出来。
  testWidgets('电脑端首页预览：默认窗口 1000x720（已连接）', (tester) async {
    if (!Platform.isWindows) return;
    await snap(
      tester,
      _home(
        connected: true,
        session: const Duration(hours: 1, minutes: 26, seconds: 12),
        notice: '节点线路已升级至 IEPL 专线，晚高峰更稳',
      ),
      'desktop_home_connected_1000x720',
      size: const Size(1000, 720),
    );
  });

  testWidgets('电脑端首页预览：默认窗口 1000x720（未连接）', (tester) async {
    if (!Platform.isWindows) return;
    await snap(tester, _home(connected: false), 'desktop_home_idle_1000x720',
        size: const Size(1000, 720));
  });

  // ── 布局回归闸门 ──────────────────────────────────────────────
  // 1.0.1 在 1000x720 及更窄的窗口里会把右栏内容挤出容器（用户看到的「重叠」）。
  // 这里把所有常见窗口尺寸都渲染一遍，只要出现 overflow / 布局异常就直接失败，
  // 保证这类问题以后再也不会漏到安装包里。
  // 不限制平台：字体不同导致的行高差异也要能兜住。
  group('窗口尺寸回归（任何尺寸都不允许布局溢出）', () {
    const sizes = <String, Size>{
      '800x600': Size(800, 600),
      '900x600': Size(900, 600),
      '1000x720': Size(1000, 720),
      '1120x720': Size(1120, 720),
      '1280x800': Size(1280, 800),
      '1366x768': Size(1366, 768),
      '1440x900': Size(1440, 900),
      '1920x1080': Size(1920, 1080),
    };

    for (final entry in sizes.entries) {
      testWidgets('${entry.key} 无布局溢出', (tester) async {
        final errors = <String>[];
        final old = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.exceptionAsString());
        addTearDown(() => FlutterError.onError = old);

        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final connected in [false, true]) {
          await tester.pumpWidget(_wrap(_home(
            connected: connected,
            session: const Duration(hours: 1, minutes: 26, seconds: 12),
            notice: '节点线路已升级至 IEPL 专线，晚高峰更稳',
          )));
          await tester.pump(const Duration(milliseconds: 900));
          await tester.pumpWidget(const SizedBox());
        }

        expect(errors, isEmpty,
            reason: '${entry.key} 出现布局异常：${errors.join(" | ")}');
      });
    }
  });
}
