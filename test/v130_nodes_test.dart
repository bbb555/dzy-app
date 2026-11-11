import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/models/server_node.dart';
import 'package:flux/services/subscription_service.dart';
import 'package:flux/utils/node_region.dart';

ServerNode _n(String name, {int? latency}) => ServerNode(
      name: name,
      address: 'h-${name.hashCode}.example.net',
      port: 443,
      protocol: 'vless',
      uuid: 'u',
      latency: latency,
    );

void main() {
  group('subscription parsing keeps every valid node', () {
    late List<ServerNode> nodes;
    late ParseStats stats;

    setUpAll(() {
      final yaml = File('test/fixtures/large_clash.yaml').readAsStringSync();
      nodes = SubscriptionService().parseNodes(yaml);
      stats = SubscriptionService.lastParseStats;
    });

    test('counts', () {
      // 官网真实格式 39 条 VLESS-WS-TLS + trojan×2 + vmess×2 + ss + hysteria2 + 3 重名 + 数字名称
      expect(nodes.length, 49, reason: stats.toString());
      expect(stats.format, 'clash');
      expect(stats.kept, 49);
      expect(stats.info, 2);
      expect(stats.unsupported,
          {'ss-plugin': 1, 'hysteria': 1, 'tuic': 1, 'socks5': 1});
      expect(stats.invalid, 0);
      expect(stats.renamed, 3);
      expect(stats.total, 55);
    });

    test('names are unique after dedup', () {
      final names = nodes.map((n) => n.name).toSet();
      expect(names.length, nodes.length);
      expect(names, contains('🇸🇬 新加坡 01 · 电信实测186M (2)'));
      expect(names, contains('🇸🇬 新加坡 01 · 电信实测186M (3)'));
      expect(names, contains('2026'));
    });

    test('no 5-node cap / order preserved / groups never shown as nodes', () {
      expect(nodes.first.name, '🇸🇬 新加坡 01 · 电信实测186M');
      expect(nodes[36].name, startsWith('🇸🇬 新加坡 37'));
      expect(nodes[38].name, '🇯🇵 日本 02 · 电信实测57M');
      for (final g in ['🚀 节点选择', '♻️ 自动选择', '🔯 故障转移', '🇸🇬 新加坡',
          '🇯🇵 日本', '🎬 视频优选', '📲 Telegram', '⚡ TG 新加坡最快', '🐟 漏网之鱼']) {
        expect(nodes.where((n) => n.name == g), isEmpty, reason: g);
      }
    });

    test('nodes sharing server / uuid / host are NOT deduped', () {
      expect(nodes[0].address, nodes[1].address);
      expect(nodes[0].address, nodes[2].address);
      expect(nodes[1].port, 2053);
      expect(nodes[2].rawConfig!['path'], startsWith('/alt'));
      final vless = nodes.take(39).toList();
      expect(vless.map((n) => n.uuid).toSet().length, 1);
      expect(vless.length, 39);
    });

    test('region grouping of the real list: 新加坡 37 + 日本 2', () {
      final g = NodeGrouping.group(nodes.take(39).toList());
      expect(g.map((e) => e.region.label).toList(), ['🇸🇬 新加坡', '🇯🇵 日本']);
      expect(g[0].all.length, 37);
      expect(g[0].top.length, 2);
      expect(g[0].hiddenCount, 35);
      expect(g[1].all.length, 2);
    });

    test('VLESS-WS-TLS fields mapped (sni, host, path+ed, fp)', () {
      final v = nodes.first;
      expect(v.protocol, 'vless');
      expect(v.network, 'ws');
      final out = v.toV2rayConfig();
      final ss = out['streamSettings'] as Map;
      expect(ss['security'], 'tls');
      expect(ss['tlsSettings']['serverName'], 'edge1.example.org');
      expect(ss['tlsSettings']['fingerprint'], 'chrome');
      expect(ss['wsSettings']['path'], '/?ed=2560');
      expect(ss['wsSettings']['host'], 'edge1.example.org');
      expect((ss['tlsSettings'] as Map).containsKey('allowInsecure'), isFalse);
      final user = (out['settings']['vnext'] as List).first['users'].first;
      expect(user['encryption'], 'none');
    });

    test('trojan numeric password, alpn list, ws transport', () {
      final t = nodes.firstWhere((n) => n.name == '🇯🇵 东京 Trojan');
      expect(t.uuid, '12345678');
      final ss = t.toV2rayConfig()['streamSettings'] as Map;
      expect(ss['security'], 'tls');
      final ws = nodes.firstWhere((n) => n.name == '🇺🇸 洛杉矶 Trojan-WS');
      final wss = ws.toV2rayConfig()['streamSettings'] as Map;
      expect(wss['network'], 'ws');
      expect(wss['wsSettings']['path'], '/tj');
      expect(wss['wsSettings']['host'], 'la.example.net');
    });

    test('vmess / ss / hysteria2 build non-empty outbounds', () {
      for (final name in ['🇸🇬 SG VMess', 'HK-VMess-TCP', 'Taiwan SS', '🇯🇵 日本 Hy2']) {
        final n = nodes.firstWhere((x) => x.name == name);
        final out = n.toV2rayConfig();
        expect(out, isNotEmpty, reason: name);
        expect(out['protocol'], isNotNull, reason: name);
      }
      final ss = nodes.firstWhere((x) => x.name == 'Taiwan SS');
      expect(ss.protocol, 'shadowsocks');
      final srv = (ss.toV2rayConfig()['settings']['servers'] as List).first;
      expect(srv['method'], 'chacha20-ietf-poly1305');
      expect(srv['password'], 'sspw');
      final hy = nodes.firstWhere((x) => x.name == '🇯🇵 日本 Hy2');
      expect(hy.toV2rayConfig()['streamSettings']['hysteriaSettings']['auth'],
          'hy2pw');
      // Xray v26：outbound settings 缺 version=2 会拒绝启动（xray run -test 验证过）
      expect(hy.toV2rayConfig()['settings']['version'], 2);
    });

    test('every kept node is connectable', () {
      for (final n in nodes) {
        expect(n.isConnectable, isTrue, reason: n.name);
      }
    });

    test('a broken YAML (duplicate key) does not lose every node', () {
      final yaml = File('test/fixtures/large_clash.yaml').readAsStringSync();
      final broken = yaml.replaceFirst(
          '    udp: true\n', '    udp: true\n    udp: false\n');
      final got = SubscriptionService().parseNodes(broken);
      expect(got.length, greaterThanOrEqualTo(48),
          reason: SubscriptionService.lastParseStats.toString());
    });

    test('server notice placeholder (127.0.0.1:1) is not shown as a node', () {
      const notice = 'mixed-port: 7890\nmode: rule\nproxies:\n'
          '  - name: "套餐已过期，请续费"\n    type: vless\n    server: 127.0.0.1\n'
          '    port: 1\n    uuid: "00000000-0000-0000-0000-000000000000"\n'
          '    tls: false\nproxy-groups: []\nrules:\n  - MATCH,DIRECT\n';
      expect(SubscriptionService().parseNodes(notice), isEmpty);
    });
  });

  group('region parsing', () {
    final cases = <String, String>{
      '🇸🇬 新加坡 01 · 电信实测186M': '新加坡',
      '🇯🇵 日本 02 · 电信实测57M': '日本',
      '🇸🇬 新加坡 03 · 多线': '新加坡',
      '🇭🇰 香港 01 · 联通': '香港',
      '🇯🇵 日本 02': '日本',
      '🇺🇸 美国 03 · 电信': '美国',
      '🇸🇬 新加坡 01': '新加坡',
      '🇹🇼 台湾 01': '台湾',
      '🇰🇷 韩国 01': '韩国',
      '🇬🇧 英国 01': '英国',
      'HK-01 IPLC': '香港',
      '[JP] Tokyo 03': '日本',
      'US-LA-02': '美国',
      'Los Angeles 01': '美国',
      'Hong Kong 05': '香港',
      'Singapore Premium': '新加坡',
      '东京 BGP': '日本',
      '洛杉矶 CN2': '美国',
      '日本 · 香港中转': '日本',
      'Taiwan SS': '台湾',
      'UK London': '英国',
      'Australia Sydney': '澳大利亚',
      '狮城 02': '新加坡',
      '🌐 全球加速 01': '其他',
      'Node 7': '其他',
      'BUSINESS': '其他',
      '2026': '其他',
    };
    cases.forEach((name, region) {
      test('$name → $region', () {
        expect(RegionParser.parse(name).name, region);
      });
    });

    test('labels carry flags', () {
      expect(RegionParser.parse('HK-01').label, '🇭🇰 香港');
      expect(RegionParser.parse('JP 01').label, '🇯🇵 日本');
      expect(RegionParser.parse('xyz').label, '🌐 其他');
    });

    test('AUSTRALIA does not match US / ISO tokens need boundaries', () {
      expect(RegionParser.parse('AUSTRALIA 1').code, 'AU');
      expect(RegionParser.parse('PLUS 1').isOther, isTrue);
    });
  });

  group('labels', () {
    test('speed badge / display / stable key', () {
      const n = '🇸🇬 新加坡 01 · 电信实测186M';
      expect(NodeLabel.speedOf(n), '186M');
      expect(NodeLabel.display(n), '新加坡 01 · 电信');
      expect(NodeLabel.stableKey(n), '🇸🇬 新加坡 01 · 电信');
      expect(NodeLabel.same(n, '🇸🇬 新加坡 01 · 电信实测139M'), isTrue);
      expect(NodeLabel.same(n, '🇸🇬 新加坡 02 · 电信实测186M'), isFalse);
      expect(NodeLabel.display('🇸🇬 新加坡 03'), '新加坡 03');
      expect(NodeLabel.speedOf('🇸🇬 新加坡 03 · 多线'), isNull);
      expect(NodeLabel.display('🇯🇵 日本 02 · 电信实测57M'), '日本 02 · 电信');
      expect(NodeLabel.display('🌐 全球加速 01'), '全球加速 01');
      expect(NodeLabel.display('HK-01'), 'HK-01');
    });
  });

  group('per-region top-2', () {
    test('before latency results: subscription order', () {
      final nodes = [
        _n('🇯🇵 日本 01'),
        _n('🇭🇰 香港 01'),
        _n('🇯🇵 日本 02'),
        _n('🇯🇵 日本 03'),
        _n('🇭🇰 香港 02'),
        _n('Node X'),
        _n('🇺🇸 美国 01'),
      ];
      final g = NodeGrouping.group(nodes);
      expect(g.map((e) => e.region.name).toList(), ['日本', '香港', '美国', '其他']);
      expect(g[0].top.map((n) => n.name), ['🇯🇵 日本 01', '🇯🇵 日本 02']);
      expect(g[0].hiddenCount, 1);
      expect(g[1].top.length, 2);
      expect(g[2].top.length, 1);
    });

    test('with latency: fastest two per region, regions by best latency', () {
      final nodes = [
        _n('🇯🇵 日本 01', latency: 300),
        _n('🇯🇵 日本 02', latency: 80),
        _n('🇯🇵 日本 03', latency: 120),
        _n('🇭🇰 香港 01', latency: 40),
        _n('🇭🇰 香港 02'), // 超时
        _n('🇭🇰 香港 03', latency: 60),
        _n('🇺🇸 美国 01'),
        _n('Other 1', latency: 5),
      ];
      final g = NodeGrouping.group(nodes);
      expect(g.map((e) => e.region.name).toList(), ['香港', '日本', '美国', '其他']);
      expect(g[0].top.map((n) => n.name), ['🇭🇰 香港 01', '🇭🇰 香港 03']);
      expect(g[1].top.map((n) => n.name), ['🇯🇵 日本 02', '🇯🇵 日本 03']);
      expect(g[2].top.single.name, '🇺🇸 美国 01');
    });

    test('auto picks fastest across ALL nodes, even ones not displayed', () {
      final nodes = [
        _n('🇭🇰 香港 01', latency: 50),
        _n('🇭🇰 香港 02', latency: 60),
        _n('🇭🇰 香港 03', latency: 70),
        _n('🇯🇵 日本 01', latency: 45),
      ];
      final g = NodeGrouping.group(nodes, perRegion: 1);
      final displayed = g.expand((e) => e.top).toList();
      expect(displayed.length, 2);
      expect(NodeGrouping.fastest(nodes)!.name, '🇯🇵 日本 01');
      // 全部线路仍然在分组里（可展开）
      expect(g.fold<int>(0, (a, e) => a + e.all.length), 4);
    });

    test('perRegion 1 and empty input', () {
      expect(NodeGrouping.group(const []), isEmpty);
      expect(NodeGrouping.fastest(const []), isNull);
    });
  });
}
