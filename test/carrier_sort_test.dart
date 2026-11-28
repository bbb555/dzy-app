import 'package:flutter_test/flutter_test.dart';
import 'package:flux/models/server_node.dart';
import 'package:flux/services/latency_test_service.dart';

ServerNode _n(String name, int? latency) => ServerNode(
      name: name,
      address: 'h-${name.hashCode}',
      port: 443,
      protocol: 'vless',
      uuid: 'u',
      latency: latency,
    );

List<String> _names(List<ServerNode> nodes) =>
    nodes.map((e) => e.name).toList();

void main() {
  // 关键样本：A 是「电信快 / 联通慢」的全量节点，B 只有联通数据，C 只有移动数据。
  // A.bandwidthMbps = 186（名字里第一个 \d+M，即电信），B = 150，C = 300。
  final a = _n('A 电信实测186M / 联通实测20M', 60);
  final b = _n('B 联通实测150M', 62);
  final c = _n('C 移动实测300M', 61);

  group('carrier = null（必须与 1.6.2 完全一致）', () {
    test('按主带宽排：A(186) > B(150) > C(300)? → 实际 A(186) 与 B/C 同档比带宽', () {
      final out = LatencyTestService.sortByLatency([b, a, c]);
      // 三者同在 60~62ms 一档；带宽 A=186 B=150 C=300 → C 最高，其次 A，再次 B
      expect(_names(out), ['C 移动实测300M', 'A 电信实测186M / 联通实测20M', 'B 联通实测150M']);
    });

    test('显式传 null 与不传参数结果一致（回归保护）', () {
      final list = [b, a, c];
      expect(_names(LatencyTestService.sortByLatency(list)),
          _names(LatencyTestService.sortByLatency(list, carrier: null)));
    });
  });

  group('carrier = 电信', () {
    test('只有 A 有电信数据 → A 进「正常带宽」档，B/C 无本网数据 → A 第一', () {
      final out = LatencyTestService.sortByLatency([b, c, a], carrier: '电信');
      expect(out.first.name, a.name);
      // B(62ms) 比 C(61ms) 慢，无本网数据时靠延迟排队
      expect(_names(out.sublist(1)), ['C 移动实测300M', 'B 联通实测150M']);
    });
  });

  group('carrier = 联通（B 从落后翻到第一）', () {
    test('A 联通实测只有 20M（低带宽档），B 150M（正常档）→ B 第一', () {
      final out = LatencyTestService.sortByLatency([a, b, c], carrier: '联通');
      expect(out.first.name, b.name);
      // 无本网数据的 A/C 靠延迟排队：A(60ms) 在 C(61ms) 之前
      expect(_names(out.sublist(1)), ['A 电信实测186M / 联通实测20M', 'C 移动实测300M']);
    });

    test('carrier 传空串等同 null（不误判成「其他」）', () {
      final list = [b, a, c];
      expect(_names(LatencyTestService.sortByLatency(list, carrier: '')),
          _names(LatencyTestService.sortByLatency(list)));
    });
  });

  group('边界', () {
    test('单网节点 + 别的 carrier 不 panic，数量不丢', () {
      final only = _n('D 移动实测45M', 30);
      final out = LatencyTestService.sortByLatency([only], carrier: '电信');
      expect(out.length, 1);
      expect(out.first.name, 'D 移动实测45M');
    });

    test('空列表 / 全无延迟不 panic', () {
      expect(LatencyTestService.sortByLatency(const [], carrier: '电信'), isEmpty);
      final x = _n('X 电信实测186M', null);
      final y = _n('Y 联通实测150M', null);
      final out = LatencyTestService.sortByLatency([x, y], carrier: '电信');
      expect(out.length, 2); // 延迟未知 → 保持原顺序
      expect(_names(out), ['X 电信实测186M', 'Y 联通实测150M']);
    });

    test('延迟仍然主导：200ms 的大带宽不越过 30ms 的节点（不饿死低带宽线路）', () {
      final slowFast = _n('P 电信实测400M', 200);
      final fastSlow = _n('Q 电信实测8M', 30);
      final out =
          LatencyTestService.sortByLatency([slowFast, fastSlow], carrier: '电信');
      expect(out.first.name, fastSlow.name);
    });

    test('识别出来的 carrier 没有对应键（如「其他」无数据）→ 全按延迟排队', () {
      final list = [b, a, c];
      // 三家都没有「其他」实测 → 带宽全视为无 → 只剩延迟：A(60) < C(61) < B(62)
      expect(_names(LatencyTestService.sortByLatency(list, carrier: '其他')),
          ['A 电信实测186M / 联通实测20M', 'C 移动实测300M', 'B 联通实测150M']);
    });
  });

  group('视频优先 + carrier', () {
    final fast = _n('V1 联通实测300M', 50); // 无电信数据
    final slow = _n('V2 电信实测60M', 400); // 电信只有 60M

    test('开视频优先按主带宽排：V1(300M) 在 V2(60M) 之前', () {
      final out =
          LatencyTestService.sortByLatency([slow, fast], videoFirst: true);
      expect(out.first.name, fast.name);
    });

    test('carrier=电信 且开视频优先：按本网带宽排，V1 无本网数据 → V2 在前', () {
      final out = LatencyTestService.sortByLatency([fast, slow],
          videoFirst: true, carrier: '电信');
      expect(out.first.name, slow.name);
    });
  });
}
