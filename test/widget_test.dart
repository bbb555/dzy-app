import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/models/server_node.dart';
import 'package:flux/widgets/node_picker_sheet.dart';

/// 官网真实格式：37 条新加坡 + 2 条日本
List<ServerNode> _realNodes() => List.generate(39, (i) {
      final name = i < 37
          ? '🇸🇬 新加坡 ${(i + 1).toString().padLeft(2, '0')} · 电信实测${100 + i}M'
          : '🇯🇵 日本 0${i - 36} · 电信实测57M';
      return ServerNode(
        name: name,
        address: '198.18.0.${i + 1}',
        port: 443,
        protocol: 'vless',
        network: 'ws',
        uuid: 'u',
        latency: i == 20 ? 30 : (i < 37 ? 200 + i : 90 + i),
      );
    });

Future<void> _open(WidgetTester t, List<ServerNode> nodes,
    {Size size = const Size(1080, 2340),
    double dpr = 2.75,
    double textScale = 1.0,
    String? current,
    bool auto = true,
    bool settle = true}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = dpr;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (c) => Center(
          child: ElevatedButton(
            onPressed: () => showModalBottomSheet(
              context: c,
              isScrollControlled: true,
              builder: (_) => NodePickerSheet(
                onNodeSelected: (_) {},
                previewNodes: nodes,
                currentName: current,
                autoMode: auto,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump(const Duration(seconds: 2));
  }
}

void main() {
  testWidgets('region groups: 2 fastest per region + 展开全部', (t) async {
    await _open(t, _realNodes());
    expect(find.text('自动选择'), findsOneWidget);
    expect(find.textContaining('共 39 条线路 · 2 个地区'), findsOneWidget);
    expect(find.text('新加坡'), findsOneWidget);
    expect(find.text('日本'), findsOneWidget);
    // 日本最快 90+37=127ms，新加坡最快 30ms → 新加坡在前；新加坡 21（30ms）排第一
    expect(find.text('新加坡 21 · 电信'), findsOneWidget);
    expect(find.text('实测 120M'), findsOneWidget);
    expect(find.text('展开全部 (37)'), findsOneWidget);
    // 收起状态：新加坡 2 条 + 日本 2 条
    expect(find.textContaining('新加坡 0'), findsOneWidget); // 新加坡 01（200ms）
    await t.tap(find.text('展开全部 (37)'));
    await t.pumpAndSettle();
    expect(find.text('收起'), findsWidgets); // 地区标题上的收起
    for (var k = 0; k < 20 && find.text('新加坡 37 · 电信').evaluate().isEmpty; k++) {
      await t.drag(find.byType(ListView), const Offset(0, -300));
      await t.pumpAndSettle();
    }
    expect(find.text('新加坡 37 · 电信'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('manually selected node stays visible when collapsed', (t) async {
    await _open(t, _realNodes(),
        current: '🇸🇬 新加坡 30 · 电信实测999M', auto: false);
    expect(find.text('新加坡 30 · 电信'), findsOneWidget);
    expect(find.text('已选'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('no overflow on a small phone at 1.3x font', (t) async {
    await _open(t, _realNodes(),
        size: const Size(720, 1280), dpr: 2.0, textScale: 1.3);
    expect(t.takeException(), isNull);
    await t.tap(find.text('展开全部 (37)'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('empty state', (t) async {
    await _open(t, const [], settle: false);
    expect(find.text('暂无可用线路'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });
}
