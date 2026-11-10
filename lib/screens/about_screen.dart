import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/dz_ui.dart';
import '../widgets/update_dialog.dart';

/// 关于队长云加速（文案与官网 / App 下载页保持一致）
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _features = [
    (Icons.bolt_rounded, '毫秒级智能选线', '连接前并发测速全部线路，自动锁定延迟最低的那一条，永远站在最快的线路上。'),
    (Icons.sync_alt_rounded, '断线无感秒切', '当前线路一旦异常，自动切换到下一条可用线路，看剧打游戏不掉线。'),
    (Icons.key_rounded, '无需输入订阅', '不用复制订阅链接、不用导入配置，官网邮箱密码一登录，线路自动就位。'),
    (
      Icons.lock_rounded,
      '金融级端到端加密',
      'VLESS + TLS 1.3 承载，流量特征与常规 HTTPS 无异，防窃听、防篡改、防重放。'
    ),
    (Icons.alt_route_rounded, '智能分流', '国内网站直连不绕路，海外流量走专线，速度与体验两不误。'),
    (Icons.radar_rounded, '10 分钟全池巡检', '系统持续对全部线路做握手探测与带宽实测，坏线自动下架，好线实时上新。'),
  ];

  static const _stats = [
    ('1200+', '全球优选入口'),
    ('30+', '覆盖地区'),
    ('10 min', '全池巡检'),
  ];

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(DzSpace.page, mq.padding.top + 10,
            DzSpace.page, mq.padding.bottom + 36),
        children: [
          Row(
            children: [
              GlassIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: '返回',
                onTap: () => Navigator.maybePop(context),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 22),
          const Entrance(child: Center(child: BrandMark(height: 92))),
          const SizedBox(height: 14),
          const Entrance(
            delayMs: 80,
            child: Column(
              children: [
                Text(
                  '新一代全球智能加速网络',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2),
                ),
                SizedBox(height: 6),
                Text(
                  '队长云加速专属客户端，一键连接全球，无需输入订阅',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Entrance(
            delayMs: 120,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x66E8C987)),
                ),
                child: const Text('旗舰版 · Version $kAppVersion',
                    style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 12,
                        letterSpacing: 1.2)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Entrance(
            delayMs: 160,
            child: GlassCard(
              gold: true,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Row(
                children: [
                  for (var i = 0; i < _stats.length; i++) ...[
                    if (i > 0)
                      Container(width: 1, height: 34, color: AppColors.border),
                    Expanded(
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: GoldText(_stats[i].$1,
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(height: 4),
                          Text(_stats[i].$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DzText.caption.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Entrance(
              delayMs: 200, child: SectionLabel('每一个细节，都为「快」和「稳」而生')),
          for (var i = 0; i < _features.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Entrance(
                delayMs: 220 + i * 60,
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          gradient: const LinearGradient(
                              colors: [Color(0x33E8C987), Color(0x0DE8C987)]),
                          border: Border.all(color: const Color(0x44E8C987)),
                        ),
                        child: Icon(_features[i].$1,
                            color: AppColors.gold, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_features[i].$2,
                                style: DzText.headline.copyWith(fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(_features[i].$3,
                                style: DzText.caption.copyWith(height: 1.55)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Entrance(
            delayMs: 600,
            child: GoldButton(
              label: '访问官网',
              icon: Icons.open_in_new_rounded,
              onPressed: () => openSite(SiteLinks.home, context),
            ),
          ),
          const SizedBox(height: 12),
          Entrance(
            delayMs: 640,
            child: GhostButton(
              label: '检查更新',
              icon: Icons.system_update_rounded,
              onPressed: () => manualCheckUpdate(context),
            ),
          ),
          const SizedBox(height: 26),
          Center(
            child: FutureBuilder<String>(
              future: resolveSiteBase(),
              builder: (_, snap) => Text(
                '© 队长云加速 · ${Uri.parse(snap.data ?? kSiteUrl).host}',
                style: DzText.caption,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
