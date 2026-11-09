import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

class IconWell extends StatelessWidget {
  final Widget icon;
  final double size;
  final Color? backgroundColor;

  const IconWell({
    super.key,
    required this.icon,
    this.size = 36,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? SurfaceLevel.inset.colorOf(context);

    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: bg,
        shape: AppShape.sm, // Continuous superellipse border
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}
