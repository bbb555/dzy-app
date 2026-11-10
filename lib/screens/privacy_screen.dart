import 'package:flutter/material.dart';

import '../widgets/dz_ui.dart';

/// 隐私政策
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = [
    (
      '1. 我们收集的信息',
      '为提供加速服务，我们只处理极少量的必要信息：\n'
          '• 账户邮箱（仅用于登录与身份验证）\n'
          '• 流量用量统计（用于计算套餐配额）\n'
          '• 订阅拉取记录（用于防共享与异常保护）\n\n'
          '我们不记录你访问的网站、DNS 查询或任何传输内容。'
    ),
    (
      '2. 信息使用',
      '上述信息仅用于：\n'
          '• 维持服务正常运行与线路巡检\n'
          '• 处理客服与售后请求\n'
          '• 防止服务被滥用'
    ),
    (
      '3. 数据安全',
      '客户端到线路全程 VLESS + TLS 1.3 加密；官网控制台接口采用 ECDH 协商 + AES-256-GCM 独立会话密钥加密，防窃听、防篡改、防重放。'
    ),
    (
      '4. 本机数据',
      '登录凭证与线路偏好仅保存在你的手机本地。App 不含广告 SDK、不含支付 SDK，也不会读取通讯录、短信、相册等个人数据。'
    ),
    ('5. 第三方', '我们不会向任何第三方出售或出租你的个人信息。套餐兑换与续费在官网完成。'),
    ('6. 政策更新', '我们可能会不时更新本隐私政策，重大变更将通过应用内公告告知。继续使用即表示你同意修订后的政策。'),
  ];

  @override
  Widget build(BuildContext context) {
    return DzSubPage(
      title: '隐私政策',
      children: [
        for (var i = 0; i < _sections.length; i++)
          Entrance(
            delayMs: 40 * i,
            dy: 12,
            child:
                DzArticleSection(title: _sections[i].$1, text: _sections[i].$2),
          ),
      ],
    );
  }
}
