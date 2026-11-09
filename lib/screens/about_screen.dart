import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/animated_background.dart';
import '../widgets/dz_ui.dart';

/// 关于队长云
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _features = [
    (Icons.verified_user_rounded, 'VLESS + TLS', '全链路加密，流量不可窥探'),
    (Icons.auto_awesome_rounded, '智能选优', '自动测速择优，失败秒级切换'),
    (Icons.alt_route_rounded, '智能分流', '国内直连、海外加速，互不打扰'),
    (Icons.visibility_off_rounded, '无日志', '不记录任何浏览内容'),
  ];

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedMeshBackground(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(DzSpace.page, top + 10, DzSpace.page, 40),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIconButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 30),
            const Entrance(child: Center(child: BrandMark(height: 96))),
            const SizedBox(height: 14),
            const Entrance(
              delayMs: 80,
              child: Center(
                child: Text('全球骨干级优选加速网络',
                    style: TextStyle(color: AppColors.textSecondary, letterSpacing: 3, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 10),
            Entrance(
              delayMs: 120,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x66E8C987)),
                  ),
                  child: const Text('Version $kAppVersion',
                      style: TextStyle(color: AppColors.gold, fontSize: 12, letterSpacing: 1.5)),
                ),
              ),
            ),
            const SizedBox(height: 34),
            for (var i = 0; i < _features.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Entrance(
                  delayMs: 180 + i * 70,
                  child: GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(colors: [Color(0x33E8C987), Color(0x0DE8C987)]),
                            border: Border.all(color: const Color(0x44E8C987)),
                          ),
                          child: Icon(_features[i].$1, color: AppColors.gold, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_features[i].$2, style: DzText.headline),
                              const SizedBox(height: 2),
                              Text(_features[i].$3, style: DzText.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Entrance(
              delayMs: 500,
              child: GoldButton(
                label: '访问官网',
                icon: Icons.open_in_new_rounded,
                onPressed: () => openSite(),
              ),
            ),
            const SizedBox(height: 12),
            Entrance(
              delayMs: 560,
              child: GhostButton(
                label: '下载最新版本',
                icon: Icons.system_update_rounded,
                onPressed: () => openSite('/app'),
              ),
            ),
            const SizedBox(height: 28),
            const Center(child: Text('© 队长云 · vip.dzgg666.de5.net', style: DzText.caption)),
          ],
        ),
      ),
    );
  }
}
