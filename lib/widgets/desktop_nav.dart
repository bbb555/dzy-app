import 'package:flutter/material.dart';
import 'dart:ui';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// 桌面端侧边导航栏 - 增加毛玻璃效果
class DesktopNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  
  const DesktopNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(
            color: AppColors.border,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Logo 区域
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.blur_on,
                    color: AppColors.accent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '队长云加速',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(color: AppColors.border, height: 1),
          
          const SizedBox(height: 16),
          
          // 导航项
          _buildNavItem(
            index: 0,
            icon: Icons.power_settings_new_rounded,
            label: AppLocalizations.of(context)?.connectionControl ?? '连接控制',
          ),
          _buildNavItem(
            index: 1,
            icon: Icons.card_giftcard_rounded,
            label: AppLocalizations.of(context)?.subscriptionPlans ?? '订阅方案',
          ),
          _buildNavItem(
            index: 2,
            icon: Icons.account_circle_outlined,
            label: AppLocalizations.of(context)?.accountInfo ?? '账户信息',
          ),
          
          const Spacer(),
          
          // 底部版本区
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'FLUX v1.0.0',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = selectedIndex == index;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onDestinationSelected(index),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected 
                  ? AppColors.accent.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: isSelected ? [
                BoxShadow(
                  color: AppColors.accent.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ] : [],
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.accent : Colors.white60,
                  size: 20,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
