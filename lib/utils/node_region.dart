import '../models/server_node.dart';

/// 线路所属地区（旗帜 + 中文名）
class NodeRegion {
  /// ISO 3166-1 alpha-2（大写）；无法识别时为 'ZZ'
  final String code;
  final String name;
  final String flag;
  const NodeRegion(this.code, this.name, this.flag);

  static const other = NodeRegion('ZZ', '其他', '🌐');

  bool get isOther => code == 'ZZ';
  String get label => '$flag $name';

  @override
  bool operator ==(Object other) => other is NodeRegion && other.code == code;
  @override
  int get hashCode => code.hashCode;
  @override
  String toString() => label;
}

/// 从线路名称识别地区：旗帜 emoji → 中文地名 / 城市 → 英文地名 / 城市 → ISO 代码。
class RegionParser {
  RegionParser._();

  /// ISO 代码 → 中文名
  static const Map<String, String> _names = {
    'HK': '香港', 'TW': '台湾', 'MO': '澳门', 'CN': '中国',
    'JP': '日本', 'KR': '韩国', 'SG': '新加坡', 'US': '美国',
    'GB': '英国', 'DE': '德国', 'FR': '法国', 'NL': '荷兰',
    'CA': '加拿大', 'AU': '澳大利亚', 'RU': '俄罗斯', 'IN': '印度',
    'TR': '土耳其', 'TH': '泰国', 'VN': '越南', 'MY': '马来西亚',
    'PH': '菲律宾', 'ID': '印度尼西亚', 'BR': '巴西', 'AR': '阿根廷',
    'MX': '墨西哥', 'AE': '阿联酋', 'IT': '意大利', 'ES': '西班牙',
    'CH': '瑞士', 'SE': '瑞典', 'PL': '波兰', 'UA': '乌克兰',
    'IE': '爱尔兰', 'FI': '芬兰', 'NO': '挪威', 'DK': '丹麦',
    'AT': '奥地利', 'BE': '比利时', 'PT': '葡萄牙', 'IL': '以色列',
    'ZA': '南非', 'EG': '埃及', 'NG': '尼日利亚', 'CL': '智利',
    'CO': '哥伦比亚', 'PE': '秘鲁', 'NZ': '新西兰', 'KH': '柬埔寨',
    'MN': '蒙古', 'KZ': '哈萨克斯坦', 'PK': '巴基斯坦', 'BD': '孟加拉',
    'SA': '沙特', 'QA': '卡塔尔', 'RO': '罗马尼亚', 'HU': '匈牙利',
    'CZ': '捷克', 'GR': '希腊', 'BG': '保加利亚', 'LU': '卢森堡',
    'IS': '冰岛', 'LT': '立陶宛', 'LV': '拉脱维亚', 'EE': '爱沙尼亚',
    'MD': '摩尔多瓦', 'RS': '塞尔维亚', 'MM': '缅甸', 'LA': '老挝',
    'NP': '尼泊尔', 'LK': '斯里兰卡', 'KE': '肯尼亚', 'MA': '摩洛哥',
  };

  /// 中文关键词（含主要城市）→ ISO。按顺序匹配，较长 / 更具体的词放前面。
  static const List<MapEntry<String, String>> _zh = [
    MapEntry('香港', 'HK'), MapEntry('港', 'HK'),
    MapEntry('台湾', 'TW'), MapEntry('臺灣', 'TW'), MapEntry('台北', 'TW'),
    MapEntry('新北', 'TW'), MapEntry('台中', 'TW'), MapEntry('高雄', 'TW'),
    MapEntry('彰化', 'TW'),
    MapEntry('澳门', 'MO'), MapEntry('澳門', 'MO'),
    MapEntry('日本', 'JP'), MapEntry('东京', 'JP'), MapEntry('東京', 'JP'),
    MapEntry('大阪', 'JP'), MapEntry('埼玉', 'JP'), MapEntry('名古屋', 'JP'),
    MapEntry('韩国', 'KR'), MapEntry('韓國', 'KR'), MapEntry('首尔', 'KR'),
    MapEntry('春川', 'KR'),
    MapEntry('新加坡', 'SG'), MapEntry('狮城', 'SG'),
    MapEntry('美国', 'US'), MapEntry('美國', 'US'), MapEntry('洛杉矶', 'US'),
    MapEntry('圣何塞', 'US'), MapEntry('硅谷', 'US'), MapEntry('西雅图', 'US'),
    MapEntry('纽约', 'US'), MapEntry('芝加哥', 'US'), MapEntry('达拉斯', 'US'),
    MapEntry('凤凰城', 'US'), MapEntry('波特兰', 'US'), MapEntry('迈阿密', 'US'),
    MapEntry('亚特兰大', 'US'), MapEntry('弗里蒙特', 'US'), MapEntry('旧金山', 'US'),
    MapEntry('拉斯维加斯', 'US'), MapEntry('华盛顿', 'US'),
    MapEntry('英国', 'GB'), MapEntry('伦敦', 'GB'),
    MapEntry('德国', 'DE'), MapEntry('法兰克福', 'DE'),
    MapEntry('法国', 'FR'), MapEntry('巴黎', 'FR'),
    MapEntry('荷兰', 'NL'), MapEntry('阿姆斯特丹', 'NL'),
    MapEntry('加拿大', 'CA'), MapEntry('多伦多', 'CA'), MapEntry('温哥华', 'CA'),
    MapEntry('蒙特利尔', 'CA'),
    MapEntry('澳大利亚', 'AU'), MapEntry('澳洲', 'AU'), MapEntry('悉尼', 'AU'),
    MapEntry('墨尔本', 'AU'),
    MapEntry('俄罗斯', 'RU'), MapEntry('莫斯科', 'RU'), MapEntry('伯力', 'RU'),
    MapEntry('印度尼西亚', 'ID'), MapEntry('印尼', 'ID'), MapEntry('雅加达', 'ID'),
    MapEntry('印度', 'IN'), MapEntry('孟买', 'IN'),
    MapEntry('土耳其', 'TR'), MapEntry('伊斯坦布尔', 'TR'),
    MapEntry('泰国', 'TH'), MapEntry('曼谷', 'TH'),
    MapEntry('越南', 'VN'), MapEntry('胡志明', 'VN'), MapEntry('河内', 'VN'),
    MapEntry('马来西亚', 'MY'), MapEntry('吉隆坡', 'MY'),
    MapEntry('菲律宾', 'PH'), MapEntry('马尼拉', 'PH'),
    MapEntry('巴西', 'BR'), MapEntry('圣保罗', 'BR'),
    MapEntry('阿根廷', 'AR'), MapEntry('墨西哥', 'MX'),
    MapEntry('阿联酋', 'AE'), MapEntry('迪拜', 'AE'),
    MapEntry('意大利', 'IT'), MapEntry('米兰', 'IT'),
    MapEntry('西班牙', 'ES'), MapEntry('马德里', 'ES'),
    MapEntry('瑞士', 'CH'), MapEntry('瑞典', 'SE'), MapEntry('波兰', 'PL'),
    MapEntry('乌克兰', 'UA'), MapEntry('爱尔兰', 'IE'), MapEntry('芬兰', 'FI'),
    MapEntry('挪威', 'NO'), MapEntry('丹麦', 'DK'), MapEntry('奥地利', 'AT'),
    MapEntry('比利时', 'BE'), MapEntry('葡萄牙', 'PT'), MapEntry('以色列', 'IL'),
    MapEntry('南非', 'ZA'), MapEntry('埃及', 'EG'), MapEntry('智利', 'CL'),
    MapEntry('新西兰', 'NZ'), MapEntry('柬埔寨', 'KH'), MapEntry('蒙古', 'MN'),
    MapEntry('哈萨克', 'KZ'), MapEntry('巴基斯坦', 'PK'), MapEntry('沙特', 'SA'),
    MapEntry('卡塔尔', 'QA'), MapEntry('罗马尼亚', 'RO'), MapEntry('匈牙利', 'HU'),
    MapEntry('捷克', 'CZ'), MapEntry('希腊', 'GR'), MapEntry('保加利亚', 'BG'),
    MapEntry('卢森堡', 'LU'), MapEntry('冰岛', 'IS'), MapEntry('缅甸', 'MM'),
    MapEntry('尼泊尔', 'NP'), MapEntry('中国', 'CN'), MapEntry('回国', 'CN'),
  ];

  /// 英文关键词（小写，整词匹配）→ ISO
  static const List<MapEntry<String, String>> _en = [
    MapEntry('hong kong', 'HK'), MapEntry('hongkong', 'HK'),
    MapEntry('taiwan', 'TW'), MapEntry('taipei', 'TW'),
    MapEntry('macau', 'MO'), MapEntry('macao', 'MO'),
    MapEntry('japan', 'JP'), MapEntry('tokyo', 'JP'), MapEntry('osaka', 'JP'),
    MapEntry('south korea', 'KR'), MapEntry('korea', 'KR'), MapEntry('seoul', 'KR'),
    MapEntry('singapore', 'SG'),
    MapEntry('united states', 'US'), MapEntry('usa', 'US'), MapEntry('america', 'US'),
    MapEntry('los angeles', 'US'), MapEntry('san jose', 'US'),
    MapEntry('silicon valley', 'US'), MapEntry('seattle', 'US'),
    MapEntry('new york', 'US'), MapEntry('chicago', 'US'), MapEntry('dallas', 'US'),
    MapEntry('phoenix', 'US'), MapEntry('miami', 'US'), MapEntry('ashburn', 'US'),
    MapEntry('united kingdom', 'GB'), MapEntry('england', 'GB'), MapEntry('london', 'GB'),
    MapEntry('germany', 'DE'), MapEntry('frankfurt', 'DE'),
    MapEntry('france', 'FR'), MapEntry('paris', 'FR'),
    MapEntry('netherlands', 'NL'), MapEntry('amsterdam', 'NL'),
    MapEntry('canada', 'CA'), MapEntry('toronto', 'CA'), MapEntry('vancouver', 'CA'),
    MapEntry('australia', 'AU'), MapEntry('sydney', 'AU'),
    MapEntry('russia', 'RU'), MapEntry('moscow', 'RU'),
    MapEntry('indonesia', 'ID'), MapEntry('jakarta', 'ID'),
    MapEntry('india', 'IN'), MapEntry('mumbai', 'IN'),
    MapEntry('turkey', 'TR'), MapEntry('istanbul', 'TR'),
    MapEntry('thailand', 'TH'), MapEntry('bangkok', 'TH'),
    MapEntry('vietnam', 'VN'), MapEntry('malaysia', 'MY'),
    MapEntry('philippines', 'PH'), MapEntry('brazil', 'BR'),
    MapEntry('argentina', 'AR'), MapEntry('mexico', 'MX'),
    MapEntry('dubai', 'AE'), MapEntry('italy', 'IT'), MapEntry('spain', 'ES'),
    MapEntry('switzerland', 'CH'), MapEntry('sweden', 'SE'), MapEntry('poland', 'PL'),
    MapEntry('ireland', 'IE'), MapEntry('china', 'CN'),
  ];

  static const Map<String, String> _isoAlias = {'UK': 'GB'};

  static final RegExp _flagRe = RegExp(r'([\u{1F1E6}-\u{1F1FF}])([\u{1F1E6}-\u{1F1FF}])', unicode: true);
  static final RegExp _isoRe = RegExp(r'(?<![A-Za-z])([A-Z]{2})(?![A-Za-z])');

  /// ISO 代码 → 旗帜 emoji
  static String flagOf(String code) {
    if (code.length != 2) return '🌐';
    final a = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final b = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([a, b]);
  }

  static NodeRegion _of(String code) {
    final name = _names[code];
    if (name == null) return NodeRegion.other;
    return NodeRegion(code, name, flagOf(code));
  }

  static final Map<String, NodeRegion> _cache = {};

  static NodeRegion parse(String name) =>
      _cache.putIfAbsent(name, () => _parse(name));

  static NodeRegion _parse(String name) {
    // 1. 旗帜 emoji（最可靠；🇺🇳 / 未知旗帜继续往下找）
    for (final m in _flagRe.allMatches(name)) {
      final code = String.fromCharCodes([
        m.group(1)!.runes.first - 0x1F1E6 + 0x41,
        m.group(2)!.runes.first - 0x1F1E6 + 0x41,
      ]);
      if (_names.containsKey(code)) return _of(code);
    }
    // 2. 中文地名 / 城市：取在名称中最早出现的（「日本 · 香港中转」算日本）
    int? bestPos;
    String? bestCode;
    for (final e in _zh) {
      final i = name.indexOf(e.key);
      if (i >= 0 && (bestPos == null || i < bestPos)) {
        bestPos = i;
        bestCode = e.value;
      }
    }
    if (bestCode != null) return _of(bestCode);
    // 3. 英文地名 / 城市（整词）
    final lower = name.toLowerCase();
    for (final e in _en) {
      final i = lower.indexOf(e.key);
      if (i < 0) continue;
      final before = i == 0 ? '' : lower[i - 1];
      final endIdx = i + e.key.length;
      final after = endIdx >= lower.length ? '' : lower[endIdx];
      if (!_isLetter(before) && !_isLetter(after)) return _of(e.value);
    }
    // 4. 独立的大写 ISO 代码（HK01、[JP]、US-LA；不会误配 AUSTRALIA 里的 US）
    for (final m in _isoRe.allMatches(name)) {
      var code = m.group(1)!;
      code = _isoAlias[code] ?? code;
      if (_names.containsKey(code)) return _of(code);
    }
    return NodeRegion.other;
  }

  static bool _isLetter(String c) =>
      c.isNotEmpty && RegExp(r'[a-z]').hasMatch(c);
}

/// 一个地区分组：展示该地区最快的 1–2 条，其余可展开
class RegionGroup {
  final NodeRegion region;

  /// 该地区全部线路（已按延迟 / 订阅顺序排好）
  final List<ServerNode> all;
  final int perRegion;
  const RegionGroup(this.region, this.all, this.perRegion);

  List<ServerNode> get top => all.take(perRegion).toList();
  int get hiddenCount => all.length > perRegion ? all.length - perRegion : 0;
  int? get bestLatency => all.isEmpty ? null : all.first.latency;
}

class NodeGrouping {
  NodeGrouping._();

  /// 按地区分组，组内按延迟从低到高（未测 / 超时的按订阅顺序排在后面），
  /// 每组展示前 [perRegion] 条。
  ///
  /// 地区排序：有测速结果时按地区最低延迟；都没有测速结果时按地区在订阅中首次出现的顺序；
  /// 「其他」始终在最后。
  static List<RegionGroup> group(List<ServerNode> nodes, {int perRegion = 2}) {
    final order = <NodeRegion, int>{};
    final buckets = <NodeRegion, List<MapEntry<int, ServerNode>>>{};
    for (var i = 0; i < nodes.length; i++) {
      final r = RegionParser.parse(nodes[i].name);
      order.putIfAbsent(r, () => i);
      (buckets[r] ??= []).add(MapEntry(i, nodes[i]));
    }
    final groups = <RegionGroup>[];
    buckets.forEach((r, list) {
      list.sort(_cmp);
      groups.add(RegionGroup(r, list.map((e) => e.value).toList(), perRegion));
    });
    groups.sort((a, b) {
      if (a.region.isOther != b.region.isOther) return a.region.isOther ? 1 : -1;
      final la = a.bestLatency, lb = b.bestLatency;
      if (la != null && lb != null && la != lb) return la.compareTo(lb);
      if (la != null && lb == null) return -1;
      if (la == null && lb != null) return 1;
      return order[a.region]!.compareTo(order[b.region]!);
    });
    return groups;
  }

  static int _cmp(MapEntry<int, ServerNode> a, MapEntry<int, ServerNode> b) {
    final la = a.value.latency, lb = b.value.latency;
    if (la != null && lb != null && la != lb) return la.compareTo(lb);
    if (la != null && lb == null) return -1;
    if (la == null && lb != null) return 1;
    return a.key.compareTo(b.key);
  }

  /// 全部线路中延迟最低的（自动选择用；不受地区展示裁剪影响）
  static ServerNode? fastest(List<ServerNode> nodes) {
    ServerNode? best;
    for (final n in nodes) {
      final l = n.latency;
      if (l == null) continue;
      if (best == null || l < best.latency!) best = n;
    }
    return best;
  }
}

/// 线路名称的展示 / 匹配辅助。
///
/// 官网线路名形如「🇸🇬 新加坡 01 · 电信实测186M」：实测速率会随巡检变化，
/// 所以记住手动选择时用 [stableKey]（去掉实测速率）匹配，避免改名后找不到原线路。
class NodeLabel {
  NodeLabel._();

  static final RegExp _speed =
      RegExp(r'\s*实测\s*(\d+(?:\.\d+)?)\s*(?:Mbps|MB/s|Mb/s|M)', caseSensitive: false);
  static final RegExp _leadFlag = RegExp(
      r'^\s*(?:[\u{1F1E6}-\u{1F1FF}]{2}|\u{1F310})\s*',
      unicode: true);

  /// 实测速率（如「186M」），没有则为 null
  static String? speedOf(String name) {
    final m = _speed.firstMatch(name);
    return m == null ? null : '${m.group(1)}M';
  }

  /// 去掉实测速率后的名称（仍含旗帜），用于跨订阅刷新匹配同一条线路
  static String stableKey(String name) {
    var s = name.replaceAll(_speed, '').trim();
    s = s.replaceAll(RegExp(r'\s*·\s*$'), '').trim();
    return s.isEmpty ? name : s;
  }

  /// 列表中展示的名称：去掉开头旗帜（地区标题已有）和实测速率
  static String display(String name) {
    final s = stableKey(name).replaceFirst(_leadFlag, '').trim();
    return s.isEmpty ? name : s;
  }

  static bool same(String? a, String? b) {
    if (a == null || b == null) return false;
    return a == b || stableKey(a) == stableKey(b);
  }
}
