import 'package:flutter_test/flutter_test.dart';
import 'package:flux/models/server_node.dart';
import 'package:flux/services/carrier_service.dart';

ServerNode _node(String name) =>
    ServerNode(name: name, address: '1.2.3.4', port: 443, protocol: 'vless');

void main() {
  group('节点名解析：多运营商', () {
    test('三网齐 → 三个键都在，主带宽取第一个 \d+M（向后兼容）', () {
      final n = _node('🇯🇵 日本 03 · 电信实测186M / 联通实测150M / 移动实测120M');
      expect(n.carrierMbps, {'电信': 186, '联通': 150, '移动': 120});
      expect(n.bandwidthMbps, 186);
    });

    test('只有联通 → 只出联通键（缺的键不能瞎补）', () {
      final n = _node('🇭🇰 香港 01 · 联通实测98M');
      expect(n.carrierMbps, {'联通': 98});
      expect(n.bandwidthMbps, 98);
    });

    test('只有移动', () {
      final n = _node('🇸🇬 新加坡 02 · 移动实测45M');
      expect(n.carrierMbps, {'移动': 45});
    });

    test('「其他」单独出现时正确归到其他', () {
      final n = _node('🇺🇸 美国 05 · 其他实测33M');
      expect(n.carrierMbps, {'其他': 33});
    });

    test('三网 + 其他并存 → 四个键（其他不被前三家吞掉）', () {
      final n = _node('电信实测186M / 联通实测150M / 移动实测120M / 其他实测60M');
      expect(n.carrierMbps,
          {'电信': 186, '联通': 150, '移动': 120, '其他': 60});
    });
  });

  group('节点名解析：边界', () {
    test('没有任何实测段 → 空表，主带宽 null', () {
      final n = _node('🇺🇸 美国 01 · 洛杉矶');
      expect(n.carrierMbps, isEmpty);
      expect(n.bandwidthMbps, isNull);
    });

    test('实测段没有运营商前缀（老格式）→ 空表，但主带宽仍然解析', () {
      final n = _node('电信-NRT-98ms-193M');
      expect(n.carrierMbps, isEmpty);
      expect(n.bandwidthMbps, 193);
    });

    test('小数与空格：电信实测 186.4 M → 186', () {
      final n = _node('香港 01 · 电信实测 186.4 M');
      expect(n.carrierMbps, {'电信': 186});
    });

    test('同一运营商重复出现 → 取大者（防御拼接/改名产生的重复段）', () {
      final n = _node('电信实测100M / 联通实测80M / 电信实测180M');
      expect(n.carrierMbps, {'电信': 180, '联通': 80});
    });

    test('0M / 非法数字不写入', () {
      final n = _node('电信实测0M / 联通实测-5M / 移动实测abcM');
      expect(n.carrierMbps, isEmpty);
    });

    test('carrierMbps 是只读的（避免外部误改缓存值）', () {
      final n = _node('电信实测186M');
      expect(() => n.carrierMbps['联通'] = 1, throwsUnsupportedError);
    });

    test('显式传入 carrierMbps 时不再走名字解析', () {
      final n = ServerNode(
        name: '电信实测186M',
        address: '1.2.3.4',
        port: 443,
        protocol: 'vless',
        carrierMbps: const {'联通': 12},
      );
      expect(n.carrierMbps, {'联通': 12});
    });

    test('copyWithName 后实测段跟着新名字重算', () {
      final n = _node('电信实测186M').copyWithName('电信实测186M (2)');
      expect(n.carrierMbps, {'电信': 186});
      expect(n.bandwidthMbps, 186);
    });
  });

  group('运营商归一化', () {
    test('中文', () {
      expect(CarrierService.normalizeCarrier('中国电信'), '电信');
      expect(CarrierService.normalizeCarrier('中国联通'), '联通');
      expect(CarrierService.normalizeCarrier('中国移动'), '移动');
      expect(CarrierService.normalizeCarrier('中国铁通'), '其他');
      expect(CarrierService.normalizeCarrier('中国广电'), '其他');
    });

    test('原生通道直接给的中文名', () {
      expect(CarrierService.normalizeCarrier('电信'), '电信');
      expect(CarrierService.normalizeCarrier('联通'), '联通');
      expect(CarrierService.normalizeCarrier('移动'), '移动');
      expect(CarrierService.normalizeCarrier('其他'), '其他');
    });

    test('英文 / AS 名', () {
      expect(CarrierService.normalizeCarrier('China Telecom'), '电信');
      expect(CarrierService.normalizeCarrier('CHINANET'), '电信');
      expect(CarrierService.normalizeCarrier('China Unicom'), '联通');
      expect(CarrierService.normalizeCarrier('CN UNICOM'), '联通');
      expect(CarrierService.normalizeCarrier('CMCC'), '移动');
      expect(CarrierService.normalizeCarrier('China Mobile'), '移动');
      expect(CarrierService.normalizeCarrier('CMNET'), '移动');
    });

    test('认不出来 / 空 → null（不硬猜成其他）', () {
      expect(CarrierService.normalizeCarrier('Google Cloud'), isNull);
      expect(CarrierService.normalizeCarrier('   '), isNull);
      expect(CarrierService.normalizeCarrier(null), isNull);
    });

    test('归一化结果与 ServerNode.carrierKeys 完全一致', () {
      expect(CarrierService.keys, ServerNode.carrierKeys);
      for (final k in CarrierService.keys) {
        expect(CarrierService.normalizeCarrier(k), k);
      }
    });
  });
}
