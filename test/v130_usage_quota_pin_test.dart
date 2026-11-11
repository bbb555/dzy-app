import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/security/pinned_http.dart';
import 'package:flux/security/pinned_roots.dart';
import 'package:flux/security/security_monitor.dart';
import 'package:flux/services/usage_service.dart';
import 'package:flux/utils/plan_quota.dart';

void main() {
  group('PlanQuota (time-based placeholders)', () {
    final now = DateTime(2026, 11, 10, 12);
    final exp = now.add(const Duration(days: 27, hours: 2)).millisecondsSinceEpoch ~/ 1000;

    test('server placeholder 1TB + u/d=0 → time-based', () {
      final q = PlanQuota.fromSubscribe({
        'u': 0,
        'd': 0,
        'transfer_enable': 1099511627776,
        'expired_at': exp,
        'plan': {'name': '月付'},
      });
      expect(q.timeBased, isTrue);
      expect(q.planName, '月付');
      expect(q.daysLeft(now), 27);
      expect(q.isExpired(now), isFalse);
    });

    test('no quota at all → time-based', () {
      expect(PlanQuota.fromSubscribe({'expired_at': exp}).timeBased, isTrue);
    });

    test('real metered data (if the server ever reports it) → not time-based', () {
      final q = PlanQuota.fromSubscribe({
        'u': 3 << 30,
        'd': 38 << 30,
        'transfer_enable': 200 << 30,
        'expired_at': exp,
      });
      expect(q.timeBased, isFalse);
      expect(q.used, 41 << 30);
    });

    test('expired / no expiry', () {
      final past = now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000;
      final q = PlanQuota.fromSubscribe({'expired_at': past, 'transfer_enable': 1099511627776});
      expect(q.isExpired(now), isTrue);
      expect(q.daysLeft(now), lessThan(0));
      expect(PlanQuota.fromSubscribe({}).daysLeft(now), isNull);
      expect(PlanQuota.fromSubscribe({'plan': {'name': '  '}}).planName, isNull);
    });
  });

  test('UsageStats.fromMap', () {
    final s = UsageStats.fromMap({
      'sessionUp': 10,
      'sessionDown': 90,
      'totalUp': 1000,
      'totalDown': 9000,
      'since': 1794000000000,
      'running': true,
    });
    expect(s.session, 100);
    expect(s.total, 10000);
    expect(s.running, isTrue);
    expect(s.since, isNotNull);
    expect(UsageStats.fromMap({}).since, isNull);
  });

  group('SecuritySignals', () {
    test('intercepting / captureSetup', () {
      expect(SecuritySignals.fromMap({}).intercepting, isFalse);
      expect(SecuritySignals.fromMap({'root': true}).intercepting, isTrue);
      expect(SecuritySignals.fromMap({'tracerPid': 1234}).instrumented, isTrue);
      expect(SecuritySignals.fromMap({'httpProxy': '10.0.0.1:8888'}).captureSetup, isTrue);
      expect(SecuritySignals.fromMap({'userCaCount': 2}).captureSetup, isTrue);
      expect(SecuritySignals.fromMap({'userCaCount': -1}).captureSetup, isFalse);
    });
  });

  group('PinnedHttp', () {
    test('only the control-plane domain is pinned', () {
      expect(PinnedHttp.isPinnedHost('vip.dzgg666.de5.net'), isTrue);
      expect(PinnedHttp.isPinnedHost('dzgg666.de5.net'), isTrue);
      expect(PinnedHttp.isPinnedHost('VIP.DZGG666.DE5.NET'), isTrue);
      expect(PinnedHttp.isPinnedHost('evil-dzgg666.de5.net'), isFalse);
      expect(PinnedHttp.isPinnedHost('www.google.com'), isFalse);
      expect(PinnedHttp.isPinnedHost('api.github.com'), isFalse);
      expect(PinnedHttp.mode, 'soft');
    });

    test('pinned roots load into a SecurityContext', () {
      expect(kPinnedRootSpki.length, greaterThanOrEqualTo(15));
      expect(PinnedHttp.pinnedContext, isNotNull);
    });

    test('isCertFailure', () {
      expect(PinnedHttp.isCertFailure(const HandshakeException('CERTIFICATE_VERIFY_FAILED')), isTrue);
      expect(PinnedHttp.isCertFailure(const SocketException('refused')), isFalse);
    });
  });

  // 需要外网：真实握手验证（CI / 无网环境下自动跳过）
  group('PinnedHttp live TLS', () {
    Future<bool> handshake(String host) async {
      final s = await SecureSocket.connect(host, 443,
          context: PinnedHttp.pinnedContext, timeout: const Duration(seconds: 8));
      s.destroy();
      return true;
    }

    test('vip.dzgg666.de5.net passes with pinned roots only', () async {
      try {
        await InternetAddress.lookup('vip.dzgg666.de5.net');
      } catch (_) {
        markTestSkipped('no network');
        return;
      }
      expect(await handshake('vip.dzgg666.de5.net'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('a host under a CA outside the pin set is rejected', () async {
      // Amazon Trust Services 根不在固定名单内
      const host = 'www.amazontrust.com';
      try {
        await InternetAddress.lookup(host);
      } catch (_) {
        markTestSkipped('no network');
        return;
      }
      Object? err;
      try {
        await handshake(host);
      } catch (e) {
        err = e;
      }
      expect(err, isA<HandshakeException>());
      expect(PinnedHttp.isCertFailure(err!), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
