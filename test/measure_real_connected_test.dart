import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/screens/home_dashboard.dart';
import 'package:flux/theme/app_theme.dart';
import 'package:flux/theme/app_colors.dart';
import 'package:flux/services/connection_supervisor.dart';
import 'package:flux/services/traffic_speed_service.dart';
import 'package:flux/services/usage_service.dart';

void main() {
  testWidgets('measure real connected view', (tester) async {
    // 模拟 Android 原生流量统计通道，让 SpeedMeter 显示完整速度卡
    const ch = MethodChannel('com.example.flux/v2ray');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async {
      if (call.method == 'trafficStats') {
        return <String, dynamic>{'up': 900000, 'down': 4200000};
      }
      return null;
    });

    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 预注入速度与用量帧（避免首帧 zero）
    TrafficSpeedService.instance.debugSet(const TrafficSample(
        down: 4200000, up: 900000, totalDown: 1523456789, totalUp: 823456789));
    UsageService.instance.debugSet(UsageStats(
        sessionUp: 823456789,
        sessionDown: 1523456789,
        totalUp: 28934905678,
        totalDown: 78234905678));

    var extents = <double>[];
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
          nodeLatency: 42,
          liveLatency: 268,
          nodeBandwidth: 193,
          nodeProtocol: 'Hysteria2',
          autoMode: false,
          phase: ConnPhase.connected,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));
    // 再等速度轮询更新
    await tester.pump(const Duration(seconds: 2));

    final scrollables = find.byType(Scrollable);
    debugPrint('MEASURE: scrollable count=${scrollables.evaluate().length}');
    for (var i = 0; i < scrollables.evaluate().length; i++) {
      final s = tester.state<ScrollableState>(scrollables.at(i));
      extents.add(s.position.maxScrollExtent);
      debugPrint(
          'MEASURE: scroll[$i] maxExtent=${s.position.maxScrollExtent.toStringAsFixed(1)} viewport=${s.position.viewportDimension.toStringAsFixed(1)}');
    }
    // 光球 + 速度卡位置
    final sectionRoot = find.byType(Column).first;
    debugPrint('MEASURE: root column height=${tester.getSize(sectionRoot).height}');
    // SpeedMeter 文本
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    debugPrint('MEASURE: visible texts: ${texts.take(12).join(" | ")}');
  });
}