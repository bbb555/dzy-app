import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/server_node.dart';
import 'v2ray_service.dart';

/// 统一 VPN 服务 - 根据平台自动选择合适的实现
class UnifiedVpnService {
  static UnifiedVpnService? _instance;
  static UnifiedVpnService get instance => _instance ??= UnifiedVpnService._();
  
  UnifiedVpnService._();
  
  final _vpnService = V2rayService();
  
  /// 连接状态流
  Stream<bool> get statusStream {
    if (kIsWeb) {
      return Stream.value(false);
    }
    // V2rayService 现在处理所有平台逻辑 (Win/Mac/Linux/Android/iOS)
    return _vpnService.statusStream;
  }
  
  /// 连接到指定节点
  Future<bool> connect(ServerNode node) async {
    if (kIsWeb) {
      debugPrint('[VPN] Web platform does not support VPN');
      return false;
    }
    
    return _vpnService.connect(node);
  }
  
  /// 断开连接
  Future<bool> disconnect() async {
    if (kIsWeb) return false;
    return _vpnService.disconnect();
  }
  
  /// 获取连接状态
  Future<bool> isConnected() async {
    if (kIsWeb) return false;
    return _vpnService.isConnected();
  }
  
  /// v1.3.0：VPN 接口与授权状态
  Future<Map<String, bool>> vpnState() async {
    if (kIsWeb) return {'running': false, 'pending': false, 'denied': false};
    return _vpnService.vpnState();
  }

  /// 释放资源
  void dispose() {
    // V2rayService 不需要显式 dispose，或者可以在其内部实现
  }
}
