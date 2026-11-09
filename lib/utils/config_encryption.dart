import 'dart:convert';
import 'dart:typed_data';

/// 配置加密工具类
/// 使用 XOR + Base64 进行简单但有效的混淆加密
class ConfigEncryption {
  // 加密密钥 - 请修改为您自己的密钥
  // 密钥在构建时通过 --dart-define=DZY_CONFIG_KEY=... 注入（来自 GitHub Actions secret），不写入源码
  static const String _encryptionKey = String.fromEnvironment(
    'DZY_CONFIG_KEY',
    defaultValue: 'YOUR_ENCRYPTION_KEY_HERE_24CH',
  );
  
  /// 加密 JSON 字符串
  static String encrypt(String plainText) {
    final keyBytes = utf8.encode(_encryptionKey);
    final plainBytes = utf8.encode(plainText);
    final encryptedBytes = Uint8List(plainBytes.length);
    
    for (var i = 0; i < plainBytes.length; i++) {
      encryptedBytes[i] = plainBytes[i] ^ keyBytes[i % keyBytes.length];
    }
    
    return base64Encode(encryptedBytes);
  }
  
  /// 解密 Base64 字符串
  static String decrypt(String encryptedText) {
    try {
      final keyBytes = utf8.encode(_encryptionKey);
      final encryptedBytes = base64Decode(encryptedText);
      final decryptedBytes = Uint8List(encryptedBytes.length);
      
      for (var i = 0; i < encryptedBytes.length; i++) {
        decryptedBytes[i] = encryptedBytes[i] ^ keyBytes[i % keyBytes.length];
      }
      
      return utf8.decode(decryptedBytes);
    } catch (e) {
      // 如果解密失败，可能是未加密的明文，直接返回
      return encryptedText;
    }
  }
  
  /// 检测内容是否已加密（通过尝试解析 JSON）
  static bool isEncrypted(String content) {
    try {
      jsonDecode(content);
      return false; // 能解析为 JSON，说明是明文
    } catch (_) {
      return true; // 不能解析，说明已加密
    }
  }
  
  /// 智能解密：如果已加密则解密，否则返回原文
  static String smartDecrypt(String content) {
    if (isEncrypted(content)) {
      return decrypt(content);
    }
    return content;
  }
}
