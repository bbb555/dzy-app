// 1.5.8 UI 预览 golden 测试：真实渲染三屏导出 PNG（非正式测试，仅用于截图）
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/models/server_node.dart';
import '../lib/screens/home_dashboard.dart';
import '../lib/screens/traffic_stats_screen.dart';
import '../lib/services/connection_supervisor.dart';
import '../lib/services/daily_usage_service.dart';
import '../lib/theme/app_colors.dart';
import '../lib/theme/app_theme.dart';
import '../lib/widgets/node_picker_sheet.dart';

Future<void> _loadFont() async {
  final f = File('assets/fonts/NotoSansSC-Regular.otf');
  if (!f.existsSync()) return;
  final bytes = await f.readAsBytes();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

List<ServerNode> _nodes() => [
      ServerNode(
          name: '香港 01',
          address: 'hk1.example.com',
          port: 443,
          protocol: 'hysteria2',
          latency: 38,
          bandwidthMbps: 193),
      ServerNode(
          name: '香港 02',
          address: 'hk2.example.com',
          port: 443,
          protocol: 'hysteria2',
          latency: 42,
          bandwidthMbps: 88),
      ServerNode(
          name: '日本 东京 01',
          address: 'jp1.example.com',
          port: 443,
          protocol: 'hysteria2',
          latency: 68,
          bandwidthMbps: 250),
      ServerNode(
          name: '日本 东京 02',
          address: 'jp2.example.com',
          port: 443,
          protocol: 'hysteria2',
          latency: 72,
          bandwidthMbps: 120),
      ServerNode(
          name: '新加坡 01',
          address: 'sg1.example.com',
          port: 443,
          protocol: 'vless',
          latency: 55,
          bandwidthMbps: 150),
      ServerNode(
          name: '台湾 01',
          address: 'tw1.example.com',
          port: 443,
          protocol: 'hysteria2',
          latency: 50,
          bandwidthMbps: 60),
      ServerNode(
          name: '韩国 首尔 01',
          address: 'kr1.example.com',
          port: 443,
          protocol: 'hysteria2',
          latency: 60,
          bandwidthMbps: 45),
      ServerNode(
          name: '美国 洛杉矶 01',
          address: 'us1.example.com',
          port: 443,
          protocol: 'vless',
          latency: 150,
          bandwidthMbps: 95),
    ];

void main() {
  setUpAll(_loadFont);

  testWidgets('preview home (首页·已连接)', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: HomeDashboard(
          onConnectPressed: () {},
          onOpenNodes: () {},
          onOpenHistory: () {},
          isConnected: true,
          statusMessage: '已连接 香港 01',
          nodeName: '🇭🇰 香港 01',
          nodeLatency: 86,
          liveLatency: 88,
          nodeBandwidth: 193,
          nodeProtocol: 'Hysteria2',
          autoMode: false,
          phase: ConnPhase.connected,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/preview_home.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('preview nodes (选线中心·筛选搜索)', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: SizedBox(
          width: 360,
          height: 740,
          child: NodePickerSheet(
            onNodeSelected: (_) {},
            previewNodes: _nodes(),
            currentName: '香港 01',
            autoMode: false,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(NodePickerSheet),
        matchesGoldenFile('goldens/preview_nodes.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('preview stats (流量统计页)', (tester) async {
    _setPhone(tester);
    final now = DateTime.now();
    final days = <String, dynamic>{};
    const data = [120, 340, 210, 560, 180, 720, 260];
    for (var i = 6; i >= 0; i--) {
      final t = now.subtract(Duration(days: i));
      final k = '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      days[k] = {'down': data[6 - i] * 1024 * 1024};
    }
    SharedPreferences.setMockInitialValues({
      'daily_usage_days_v2': jsonEncode(days),
      'daily_usage_lines_v2': jsonEncode({
        '香港 01': {'down': 380 * 1048576},
        '新加坡 01': {'down': 210 * 1048576},
        '日本 东京 01': {'down': 150 * 1048576},
        '美国 洛杉矶 01': {'down': 88 * 1048576},
      }),
    });
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const TrafficStatsScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(TrafficStatsScreen),
        matchesGoldenFile('goldens/preview_stats.png'));
    await tester.pumpWidget(const SizedBox());
    DailyUsageService.instance.stop();
  });
}