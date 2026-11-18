import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'diag_log.dart';

/// v1.5.12：系统级隧道校验 —— 治「假连接」。
///
/// 背景：以前的「已连接」只证明 Xray 内核能经线路出网（探测入站是本地 127.0.0.1，
/// 不经过系统 TUN）。当系统的 VPN 通道没有真正接管流量时（被其他 VPN/代理类 App 抢占、
/// VPN 授权被回收、VpnService 被系统停掉），就会出现「显示已连接、实际一点流量都没有」。
///
/// 这个校验直接问原生层三件事，缺一不可：
///  1. VpnService 是否在运行（isVpnRunning）；
///  2. 系统是否把 VPN 网络当作「活动网络」（ConnectivityManager 的 TRANSPORT_VPN）；
///  3. TUN 计数是否在采样窗口里增长（hev-socks5-tunnel 自带的计数器）。
/// 第 1、2 条不满足 → 隧道没有接管系统流量，不再对外显示「已连接」。
class TunnelCheck {
  /// 隧道确实建立且被系统当作活动网络
  final bool tunnelUp;

  /// 采样窗口内 TUN 计数有增长（只作参考：其他 App 恰好没流量时也会是 false）
  final bool trafficFlowing;

  final int upBytes;
  final int downBytes;

  /// 关键细节/失败原因，直接进诊断日志
  final String? note;

  const TunnelCheck({
    required this.tunnelUp,
    required this.trafficFlowing,
    this.upBytes = 0,
    this.downBytes = 0,
    this.note,
  });

  bool get ok => tunnelUp;

  @override
  String toString() =>
      'TunnelCheck(tunnelUp=$tunnelUp, flowing=$trafficFlowing, up=$upBytes, down=$downBytes'
      '${note == null ? '' : ', note=$note'})';
}

class TunnelVerifier {
  TunnelVerifier._();

  static final TunnelVerifier instance = TunnelVerifier._();

  static const MethodChannel _ch = MethodChannel('com.example.flux/v2ray');

  /// 原生侧诊断快照（VPN 状态、TUN 计数、权限、机型、内核日志大小…）
  Future<Map<String, Object?>?> diagInfo() async {
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('diagInfo');
      if (r == null) return null;
      return <String, Object?>{
        for (final e in r.entries) '${e.key}': e.value,
      };
    } catch (e) {
      DiagLog.instance.error('tunnel', '读取原生诊断信息失败: $e');
      return null;
    }
  }

  /// 内核（Xray）最近输出，含启动错误、握手失败等一眼可见的原因
  Future<String> readCoreLog() async {
    try {
      return await _ch.invokeMethod<String>('readCoreLog') ?? '';
    } catch (e) {
      return '内核日志读取失败: $e';
    }
  }

  /// 采样 TUN 计数做判断。[sample] 为两次快照之间的间隔。
  Future<TunnelCheck> check(
      {Duration sample = const Duration(milliseconds: 2000)}) async {
    // 只有 Android 有 VpnService/TUN 这套判定；桌面端保持旧行为
    if (!Platform.isAndroid) {
      return const TunnelCheck(
          tunnelUp: true, trafficFlowing: true, note: '非 Android 平台，跳过隧道校验');
    }
    final a = await diagInfo();
    if (a == null) {
      return const TunnelCheck(
          tunnelUp: false, trafficFlowing: false, note: '拿不到原生状态（通道异常）');
    }
    final running = a['vpnRunning'] == true;
    final transport = a['vpnTransport'] == true;
    // v1.5.14：本 App 用 addDisallowedApplication 把自己排除在 VPN 之外，本 UID 的
    // activeNetwork 永远看不到 TRANSPORT_VPN —— 只认这一条会把「隧道其实已接管」
    // 误判成没接管（v1.5.12/v1.5.13 每次连接都命中，连上即被拆）。补一条原生侧不
    // 依赖 per-UID 网络视图的判据：VpnService 在跑 + 本机隧道计数器可读 = 已建立。
    final tunnelOk = a['vpnTunnelUp'] == true;
    final coreAlive = a['xrayAlive'] == true;
    final up1 = _num(a['tunUp']);
    final down1 = _num(a['tunDown']);

    if (!running) {
      return TunnelCheck(
        tunnelUp: false,
        trafficFlowing: false,
        upBytes: up1,
        downBytes: down1,
        note: 'VpnService 未运行（isVpnRunning=false）',
      );
    }
    if (!transport && !tunnelOk) {
      return TunnelCheck(
        tunnelUp: false,
        trafficFlowing: false,
        upBytes: up1,
        downBytes: down1,
        note: '系统未把 VPN 设为活动网络且本机隧道未建立：隧道没接管流量（多半被其他 VPN/代理类 App 抢占或授权被回收）',
      );
    }

    await Future<void>.delayed(sample);
    final b = await diagInfo();
    final up2 = b == null ? up1 : _num(b['tunUp']);
    final down2 = b == null ? down1 : _num(b['tunDown']);
    final delta = (up2 - up1) + (down2 - down1);
    final flowing = delta > 512;
    return TunnelCheck(
      tunnelUp: true,
      trafficFlowing: flowing,
      upBytes: up2,
      downBytes: down2,
      note: flowing
          ? null
          : '隧道已建立，但采样窗口内 TUN 无流量'
              '${coreAlive ? '' : '；且内核进程已退出'}',
    );
  }

  int _num(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
