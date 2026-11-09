import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';
import '../widgets/animated_card.dart';

class TosScreen extends StatelessWidget {
  const TosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Center(
                            child: Text(
                              '服务条款',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48), // Balance the icon button
                      ],
                    ),
                    const SizedBox(height: 24),
                    AnimatedCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _SectionTitle('1. 接受条款'),
                          _SectionText(
                            '欢迎使用队长云。通过下载、安装或使用本应用，即表示您同意遵守以下服务条款。\n'
                            '如果您不同意这些条款，请立即停止使用本服务。',
                          ),
                          SizedBox(height: 24),
                          _SectionTitle('2. 服务内容'),
                          _SectionText(
                            '队长云提供网络加速和加密传输服务。我们致力于提供高可用性的服务，但不保证服务永远不会中断或没有错误。',
                          ),
                          SizedBox(height: 24),
                          _SectionTitle('3. 禁止用途'),
                          _SectionText(
                            '您同意不使用本服务从事以下活动：\n'
                            '• 违反任何适用的法律或法规\n'
                            '• 发送垃圾邮件或进行网络攻击（如 DDoS）\n'
                            '• 访问、上传或传播非法内容（如儿童色情、恐怖主义内容）\n'
                            '• 侵犯他人的知识产权\n'
                            '• 对本服务进行逆向工程或破解\n\n'
                            '一旦发现违规行为，我们将立即终止您的账户且不予退款。',
                          ),
                          SizedBox(height: 24),
                          _SectionTitle('4. 免责声明'),
                          _SectionText(
                            '本服务按"现状"提供。在法律允许的最大范围内，我们不承担因使用本服务而导致的任何直接、间接或附带的损失责任。',
                          ),
                          SizedBox(height: 24),
                          _SectionTitle('5. 退款政策'),
                          _SectionText(
                            '具体的退款政策请参考您的购买凭证或联系客服处理。通常情况下，虚拟商品一旦使用将不支持退款。',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _SectionText extends StatelessWidget {
  final String text;
  const _SectionText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.6,
        ),
      ),
    );
  }
}
