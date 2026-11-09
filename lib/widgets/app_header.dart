import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'dz_ui.dart';

/// 应用顶部品牌标题（金色字标）
class AppHeader extends StatelessWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        children: [
          BrandMark(height: 52),
          SizedBox(height: 8),
          Text('全球优选加速网络', style: DzText.overline),
        ],
      ),
    );
  }
}
