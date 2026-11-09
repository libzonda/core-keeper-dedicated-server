import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// DelayChip with Tabular Numeric Delay & Three-tier Color Palette
class DelayChip extends StatelessWidget {
  final int? delay;

  const DelayChip({super.key, required this.delay});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = delayColorOf(delay, isDark);

    final String text;
    if (delay == null || delay! <= 0) {
      text = 'Timeout';
    } else {
      text = '$delay ms';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.15),
        shape: AppShape.full,
      ),
      child: Text(
        text,
        style: AppTextStyle.caption1.of(
          context,
          emphasized: true,
          color: color,
          tabular: true,
        ),
      ),
    );
  }
}

