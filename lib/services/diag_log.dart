import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// v1.5.12：客户端诊断日志。
///
/// 为什么要有它：连接类问题（「连上了但没网」「显示成功其实是假的」）以前只能靠猜——
/// 日志只在 debug 模式打控制台，Release 包里看不到任何现场，也没法让用户把现场发回来。
/// 现在所有关键步骤都记在这里：
///  · 内存环形缓冲（最近 [maxEntries] 条）→ App 内「连接诊断」页直接看、一键复制；
///  · 落盘到应用支持目录 diag.log（滚动，最多 [maxFileBytes]）→ 断网也能导出；
///  · 每条带时间/级别/模块，错误单列并在页面上标红，卡在哪一步一眼可见。
class DiagEntry {
  final DateTime at;

  /// info | warn | error
  final String level;
  final String tag;
  final String msg;

  const DiagEntry(this.at, this.level, this.tag, this.msg);

  bool get isError => level == 'error';
  bool get isWarn => level == 'warn';

  String get stamp =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}.${(at.millisecond ~/ 10).toString().padLeft(2, '0')}';

  String get line => '$stamp [${level.toUpperCase()}] $tag: $msg';

  @override
  String toString() => line;
}

class DiagLog {
  DiagLog._();

  static final DiagLog instance = DiagLog._();

  static const int maxEntries = 1500;
  static const int maxFileBytes = 512 * 1024;

  final Queue<DiagEntry> _buf = Queue<DiagEntry>();
  File? _file;
  bool _initStarted = false;

  List<DiagEntry> get entries => _buf.toList(growable: false);
  int get errorCount => _buf.where((e) => e.isError).length;
  bool get hasErrors => errorCount > 0;

  /// 记录一条。[level] 取 info / warn / error。
  void log(String tag, String msg, {String level = 'info'}) {
    final e = DiagEntry(DateTime.now(), level, tag, msg);
    _buf.addLast(e);
    while (_buf.length > maxEntries) {
      _buf.removeFirst();
    }
    if (kDebugMode) debugPrint('[diag] ${e.line}');
    unawaited(_persist(e));
  }

  void info(String tag, String msg) => log(tag, msg);
  void warn(String tag, String msg) => log(tag, msg, level: 'warn');
  void error(String tag, String msg) => log(tag, msg, level: 'error');

  /// App 启动时调用一次即可；失败不影响功能（只是没有落盘副本）。
  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}diag.log');
      if (!await f.exists()) {
        await f.create(recursive: true);
      }
      try {
        final len = await f.length();
        if (len > maxFileBytes) {
          final txt = await f.readAsString();
          final keep = txt.substring(txt.length - (maxFileBytes ~/ 2));
          await f.writeAsString(keep);
        }
      } catch (_) {}
      _file = f;
    } catch (_) {
      _file = null;
    }
  }

  Future<void> _persist(DiagEntry e) async {
    if (_file == null) {
      if (!_initStarted) await init();
      if (_file == null) return;
    }
    try {
      await _file!.writeAsString('${e.line}\n', mode: FileMode.append);
    } catch (_) {
      // 落盘失败不影响连接，忽略
    }
  }

  /// 导出为纯文本（默认含最后 [maxLines] 行，errorsOnly 只看错误）
  String text({bool errorsOnly = false, int maxLines = 1200}) {
    final src = errorsOnly ? _buf.where((e) => e.isError).toList() : entries;
    final list = src.length > maxLines ? src.sublist(src.length - maxLines) : src;
    final buf = StringBuffer();
    buf.writeln('# 队长云加速 · 连接诊断日志');
    buf.writeln('# 导出时间: ${DateTime.now().toIso8601String()}');
    buf.writeln('# 条目: ${list.length}${errorsOnly ? '（仅错误）' : ''}');
    buf.writeln('');
    for (final e in list) {
      buf.writeln(e.line);
    }
    return buf.toString();
  }

  Future<void> clear() async {
    _buf.clear();
    try {
      await _file?.writeAsString('');
    } catch (_) {}
  }
}
