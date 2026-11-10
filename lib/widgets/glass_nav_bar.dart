import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// 悬浮玻璃导航：两项（连接 / 我的），金色滑块指示
class GlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const _items = [
    (Icons.bolt_rounded, '连接'),
    (Icons.person_rounded, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(56, 0, 56, bottom + 18),
      // 不使用 BackdropFilter：导航栏叠在做交叉淡入的页面之上，实时模糊会在切换时闪烁，
      // 且低端机开销大。改为高不透明度深蓝渐变 + 投影，观感一致、切换稳定。
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
                color: Color(0x99000000),
                blurRadius: 28,
                offset: Offset(0, 12),
                spreadRadius: -8)
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF0141C3D), Color(0xF5090E20)],
              ),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth / _items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 420),
                      curve: DzMotion.emphasized,
                      left: w * selectedIndex,
                      top: 0,
                      bottom: 0,
                      width: w,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          gradient: AppColors.goldGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.goldMid.withValues(alpha: 0.35),
                              blurRadius: 16,
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          Expanded(child: _item(context, i)),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i) {
    final sel = i == selectedIndex;
    final color = sel ? AppColors.onGold : AppColors.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!sel) HapticFeedback.selectionClick();
        onDestinationSelected(i);
      },
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: sel ? 1.08 : 1,
              duration: DzMotion.base,
              child: Icon(_items[i].$1, size: 20, color: color),
            ),
            const SizedBox(width: 6),
            AnimatedDefaultTextStyle(
              duration: DzMotion.base,
              style: DefaultTextStyle.of(context).style.merge(TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 1.5,
                  )),
              child: Text(_items[i].$2, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}
