import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/diag_log.dart';
import '../services/tunnel_verifier.dart';
import '../theme/app_colors.dart';

/// v1.5.12：连接诊断页。
///
/// 目的只有一个：连接出问题时，队长（和客服）一眼看出卡在哪一步，而不是靠猜。
///  · 上半部分是原生层的实时状态：VPN 服务是否在跑、系统有没有把 VPN 当活动网络、
///    TUN 计数、内核进程是否存活、权限/省电限制、机型与 ABI；
///  · 中间是内核（Xray）自己的输出（Release 包里唯一能拿到的内核现场）；
///  · 下半部分是 App 的连接过程日志，错误标红，可只看错误。
/// 「复制全部」把三部分合成一段文本，方便直接贴给我们定位。
class DiagScreen extends StatefulWidget {
  const DiagScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const DiagScreen());

  @override
  State<DiagScreen> createState() => _DiagScreenState();
}

class _DiagScreenState extends State<DiagScreen> {
  Map<String, Object?>? _info;
  TunnelCheck? _check;
  String _coreLog = '';
  bool _busy = true;
  bool _errorsOnly = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final info = await TunnelVerifier.instance.diagInfo();
    final chk = await TunnelVerifier.instance.check(
        sample: const Duration(milliseconds: 1200));
    final core = await TunnelVerifier.instance.readCoreLog();
    DiagLog.instance.info('diag', '手动检测：$chk');
    if (!mounted) return;
    setState(() {
      _info = info;
      _check = chk;
      _coreLog = core;
      _busy = false;
    });
  }

  String _s(String key, {String unit = ''}) {
    final v = _info?[key];
    if (v == null) return '—';
    return '$v$unit';
  }

  String _yn(Object? v, {String yes = '是', String no = '否'}) {
    if (v == true) return yes;
    if (v == false) return no;
    return '未知';
  }

  String _bytes(int b) {
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }

  /// 一句话结论：出问题时这里就是原因
  String get _verdict {
    final c = _check;
    if (c == null) return '尚未检测';
    if (!c.tunnelUp) return c.note ?? '隧道未接管系统流量';
    if (!c.trafficFlowing) return '隧道已建立；采样期间 TUN 无流量（其他 App 没流量时也会这样，仅参考）';
    return '隧道工作正常，流量已在走';
  }

  bool get _verdictBad => _check != null && !_check!.tunnelUp;

  String _reportText() {
    final b = StringBuffer();
    b.writeln('# 队长云加速 · 连接诊断报告');
    b.writeln('时间: ${DateTime.now().toIso8601String()}');
    b.writeln('结论: $_verdict');
    b.writeln('');
    b.writeln('## 客户端与设备');
    b.writeln('版本: ${_s('appVersion')}  SDK: ${_s('sdk')}  ABI: ${_s('abi')}');
    b.writeln('机型: ${_s('model')}');
    b.writeln('');
    b.writeln('## 隧道状态');
    b.writeln('VpnService 运行: ${_yn(_info?['vpnRunning'])}');
    b.writeln('隧道停止原因: ${(_info?['lastStopReason'] as String?)?.isNotEmpty == true ? _info?['lastStopReason'] : '（本次会话没有停过）'}');
    b.writeln('系统 VPN 活动网络: ${_yn(_info?['vpnTransport'])}');
    b.writeln('系统 VPN 网络数: ${_s('vpnCount')}（>1 说明有别的 VPN/代理 App 在抢通道）');
    b.writeln('内核进程存活: ${_yn(_info?['xrayAlive'])}');
    b.writeln('TUN 上传/下载: ${_bytes(_check?.upBytes ?? 0)} / ${_bytes(_check?.downBytes ?? 0)}'
        '（来源 ${_s('tunSrc')}）');
    b.writeln('需要 VPN 授权: ${_yn(_info?['vpnPermissionNeeded'])}');
    b.writeln('省电限制中: ${_yn(_info?['batteryOptimized'])}（是 = 系统可能冻结后台）');
    b.writeln('');
    b.writeln('## 内核(Xray)输出');
    b.writeln(_coreLog.isEmpty ? '(空)' : _coreLog);
    b.writeln('');
    b.writeln('## App 连接日志');
    b.write(DiagLog.instance.text(errorsOnly: false, maxLines: 600));
    return b.toString();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _reportText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('诊断信息已复制到剪贴板')));
  }

  Future<void> _clear() async {
    await DiagLog.instance.clear();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entries = DiagLog.instance.entries
        .where((e) => !_errorsOnly || e.isError)
        .toList(growable: false)
        .reversed
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('连接诊断'),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '复制全部',
            onPressed: _copy,
            icon: const Icon(Icons.copy_all),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Card(
              color: _verdictBad
                  ? const Color(0x33FF5252)
                  : const Color(0x2217E9A0),
              child: ListTile(
                leading: Icon(
                  _verdictBad ? Icons.error_outline : Icons.verified_outlined,
                  color: _verdictBad ? const Color(0xFFFF8A80) : const Color(0xFF17E9A0),
                ),
                title: Text(_busy ? '正在检测…' : _verdict),
                subtitle: Text('点右上角「复制全部」可把这份报告直接发给我们'),
              ),
            ),
            _section('隧道状态', [
              _kv('VpnService 运行', _yn(_info?['vpnRunning'])),
              _kv(
                  '隧道停止原因',
                  (_info?['lastStopReason'] as String?)?.isNotEmpty == true
                      ? (_info?['lastStopReason'] as String)
                      : '本次会话没有停过'),
              _kv('系统 VPN 活动网络', _yn(_info?['vpnTransport']),
                  warn: _info != null && _info!['vpnTransport'] != true),
              _kv('系统 VPN 网络数', _s('vpnCount')),
              _kv('内核进程存活', _yn(_info?['xrayAlive']),
                  warn: _info != null && _info!['xrayAlive'] != true),
              _kv('TUN 上传 / 下载',
                  '${_bytes(_check?.upBytes ?? 0)} / ${_bytes(_check?.downBytes ?? 0)}'),
              _kv('TUN 计数来源', _s('tunSrc')),
              _kv('需要重新授权', _yn(_info?['vpnPermissionNeeded'])),
              _kv('省电限制', _yn(_info?['batteryOptimized']),
                  warn: _info != null && _info!['batteryOptimized'] == true),
            ]),
            _section('设备', [
              _kv('客户端版本', _s('appVersion')),
              _kv('机型', _s('model')),
              _kv('Android SDK', _s('sdk')),
              _kv('ABI', _s('abi')),
            ]),
            _section(
              '内核(Xray)输出',
              [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: SelectableText(
                    _coreLog.isEmpty ? '(内核还没有输出)' : _coreLog,
                    style: const TextStyle(
                        fontSize: 11.5, fontFamily: 'monospace', height: 1.35),
                  ),
                ),
              ],
              trailing: TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _coreLog));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('内核日志已复制')));
                  }
                },
                child: const Text('复制'),
              ),
            ),
            Row(
              children: [
                const Expanded(
                    child: Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('App 连接日志（最近在下）',
                      style: TextStyle(fontSize: 13, color: Colors.white70)),
                )),
                Switch(
                  value: _errorsOnly,
                  onChanged: (v) => setState(() => _errorsOnly = v),
                ),
                const Text('只看错误', style: TextStyle(fontSize: 12)),
                IconButton(
                  tooltip: '清空日志',
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无日志', style: TextStyle(color: Colors.white38)),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in entries.take(300))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: SelectableText(
                          e.line,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            height: 1.35,
                            color: e.isError
                                ? const Color(0xFFFF8A80)
                                : (e.isWarn
                                    ? const Color(0xFFFFD54F)
                                    : Colors.white70),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children, {Widget? trailing}) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
            child: Row(
              children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white))),
                if (trailing != null) trailing,
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 132,
              child: Text(k,
                  style: const TextStyle(fontSize: 12.5, color: Colors.white60))),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    fontSize: 12.5,
                    color: warn ? const Color(0xFFFF8A80) : Colors.white)),
          ),
        ],
      ),
    );
  }
}
