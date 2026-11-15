import 'package:flutter/material.dart';

/// 节点工具类
class NodeUtils {
  /// 从节点名解析实测带宽（Mbps），解析不到返回 null（如「98ms-193M」→ 193）
  static int? extractBandwidthMbps(String name) {
    if (name.isEmpty) return null;
    final s = name.toUpperCase();
    final byte = RegExp(r'(\d+(?:\.\d+)?)\s*MB/S').firstMatch(s);
    if (byte != null) {
      final v = double.tryParse(byte.group(1)!);
      if (v != null && v > 0) return (v * 8).round().clamp(1, 9999);
    }
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*M(?!S)\b').firstMatch(s);
    if (m != null) {
      final v = double.tryParse(m.group(1)!);
      if (v != null && v >= 0.5) return v.round().clamp(1, 9999);
    }
    return null;
  }
  static String extractCountry(String name, {BuildContext? context}) {
    String? countryKey;

    // 优先匹配中文国家名
    const chineseNames = [
      '中国', '美国', '香港', '台湾', '日本', '韩国', '新加坡', 
      '英国', '德国', '法国', '加拿大', '澳大利亚', '荷兰', 
      '俄罗斯', '印度', '巴西', '土耳其', '墨西哥',
    ];
    for (final cn in chineseNames) {
      if (name.contains(cn)) {
        countryKey = cn; // 暂时直接用中文名作为 Key
        break;
      }
    }

    if (countryKey == null) {
      // 常见国家代码映射
      final countryMap = {
        'CN': '中国', 'US': '美国', 'HK': '香港', 'TW': '台湾', 'JP': '日本',
        'KR': '韩国', 'SG': '新加坡', 'UK': '英国', 'GB': '英国', 'DE': '德国',
        'FR': '法国', 'CA': '加拿大', 'AU': '澳大利亚', 'NL': '荷兰', 'RU': '俄罗斯',
        'IN': '印度', 'BR': '巴西', 'TR': '土耳其', 'MX': '墨西哥',
      };

      final upperName = name.toUpperCase();
      for (var entry in countryMap.entries) {
        if (upperName.contains(entry.key)) {
          countryKey = entry.value;
          break;
        }
      }
    }

    if (countryKey == null) {
      // 尝试提取常见英文名
       final countryNames = {
        'HONG KONG': '香港', 'HONGKONG': '香港', 'TAIWAN': '台湾', 'JAPAN': '日本',
        'SINGAPORE': '新加坡', 'KOREA': '韩国', 'SOUTH KOREA': '韩国', 'CHINA': '中国',
        'USA': '美国', 'UNITED STATES': '美国', 'UK': '英国', 'UNITED KINGDOM': '英国',
      };
      
      final upperName = name.toUpperCase();
      for (var entry in countryNames.entries) {
        if (upperName.contains(entry.key)) {
          countryKey = entry.value;
          break;
        }
      }
    }

    // 如果还没有找到，返回原始名称
    if (countryKey == null) {
      return name.length > 10 ? name.substring(0, 10) : name;
    }

    // 如果有 Context，尝试根据语言返回
    if (context != null) {
      final locale = Localizations.localeOf(context);
      if (locale.languageCode == 'en') {
        return _getEnglishName(countryKey);
      }
    }

    return countryKey;
  }

  static String _getEnglishName(String chineseName) {
    const map = {
      '中国': 'China',
      '美国': 'USA',
      '香港': 'Hong Kong',
      '台湾': 'Taiwan',
      '日本': 'Japan',
      '韩国': 'Korea',
      '新加坡': 'Singapore',
      '英国': 'UK',
      '德国': 'Germany',
      '法国': 'France',
      '加拿大': 'Canada',
      '澳大利亚': 'Australia',
      '荷兰': 'Netherlands',
      '俄罗斯': 'Russia',
      '印度': 'India',
      '巴西': 'Brazil',
      '土耳其': 'Turkey',
      '墨西哥': 'Mexico',
    };
    return map[chineseName] ?? chineseName;
  }
}
