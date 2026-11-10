import 'package:flutter/material.dart';

import '../widgets/dz_ui.dart';

/// 服务条款
class TosScreen extends StatelessWidget {
  const TosScreen({super.key});

  static const _sections = [
    ('1. 接受条款', '欢迎使用队长云。下载、安装或使用本应用，即表示你同意遵守以下服务条款；如不同意，请停止使用本服务。'),
    ('2. 服务内容', '队长云提供全球优选加速与加密传输服务。我们持续巡检全部线路、致力于高可用，但不保证服务永不中断或没有错误。'),
    (
      '3. 禁止用途',
      '你同意不使用本服务从事以下活动：\n'
          '• 违反任何适用的法律或法规\n'
          '• 发送垃圾邮件或进行网络攻击（如 DDoS）\n'
          '• 访问、上传或传播非法内容\n'
          '• 侵犯他人的知识产权\n'
          '• 对本服务进行逆向工程或破解\n\n'
          '一经发现违规，我们有权立即终止账户且不予退款。'
    ),
    ('4. 账户与订阅', '每位用户拥有独立的订阅令牌，请勿与他人共享账号。异地滥用会触发自动保护；如怀疑泄露，可在官网控制台一键重置。'),
    ('5. 免责声明', '本服务按「现状」提供。在法律允许的最大范围内，我们不承担因使用本服务而导致的任何直接、间接或附带损失。'),
    ('6. 续费与退款', '套餐通过官网兑换码开通或续期。虚拟商品一经兑换使用，原则上不支持退款；特殊情况请联系官网客服处理。'),
  ];

  @override
  Widget build(BuildContext context) {
    return DzSubPage(
      title: '服务条款',
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
