import 'package:flutter/material.dart';

/// Pulsing Telemetry Dot
/// Breathes with a physical organic glow when active (e.g. Server Running)
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool isPulsing;

  const PulsingDot({
    super.key,
    required this.color,
    this.size = 8.0,
    this.isPulsing = false,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPulsing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing != oldWidget.isPulsing) {
      if (widget.isPulsing) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPulsing) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final scale = 1.0 + (t * 1.5);
        final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.6;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Breathing Ripple Halo
            Transform.scale(
              scale: scale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Core Dot
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

