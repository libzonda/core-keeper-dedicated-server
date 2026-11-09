import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Elastic Squash & Stretch Switch
/// - Semicircular stadium pill track (StadiumBorder)
/// - Crisp white circular thumb (24dp) with natural drop shadow
/// - Squashes & stretches into a pill (32dp) while held
/// - Snaps across with smooth 280ms spring motion
class ElasticSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const ElasticSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const double trackWidth = 50.0;
  static const double trackHeight = 30.0;
  static const double _inset = 3.0;
  static const double _thumbSize = 24.0;
  static const double _heldThumbWidth = 32.0;

  @override
  State<ElasticSwitch> createState() => _ElasticSwitchState();
}

class _ElasticSwitchState extends State<ElasticSwitch> with TickerProviderStateMixin {
  late final AnimationController _toggleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.value ? 1.0 : 0.0,
  );

  late final Animation<double> _position = CurvedAnimation(
    parent: _toggleController,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInOutCubic,
  );

  late final AnimationController _pressController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  bool get _isEnabled => widget.onChanged != null;

  @override
  void didUpdateWidget(ElasticSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        if (_toggleController.status != AnimationStatus.completed) {
          _toggleController.forward();
        }
      } else {
        if (_toggleController.status != AnimationStatus.dismissed) {
          _toggleController.reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    _toggleController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_isEnabled) {
      final nextVal = !widget.value;
      if (nextVal) {
        _toggleController.forward();
      } else {
        _toggleController.reverse();
      }
      widget.onChanged!(nextVal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final offTrackColor = isDark ? const Color(0xFF39393D) : const Color(0xFFE5E5EA);

    return MouseRegion(
      cursor: _isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (_isEnabled) _pressController.forward();
        },
        onTapUp: (_) {
          if (_isEnabled) _pressController.reverse();
        },
        onTapCancel: () {
          if (_isEnabled) _pressController.reverse();
        },
        onTap: _isEnabled ? _handleTap : null,
        child: AnimatedBuilder(
          animation: Listenable.merge([_position, _pressController]),
          builder: (context, _) {
            final t = _position.value.clamp(0.0, 1.0);
            final pressVal = _pressController.value;

            // Track color smoothly lerps between off-grey and primary blue
            final trackColor = Color.lerp(offTrackColor, primaryColor, t)!;

            // Thumb width stretches when held
            final currentThumbWidth = ElasticSwitch._thumbSize +
                (ElasticSwitch._heldThumbWidth - ElasticSwitch._thumbSize) * pressVal;

            // Travel distance
            const maxTravel = ElasticSwitch.trackWidth - (ElasticSwitch._inset * 2) - ElasticSwitch._thumbSize;
            final leftOffset = ElasticSwitch._inset + (maxTravel * t) -
                (currentThumbWidth - ElasticSwitch._thumbSize) * t;

            return Container(
              width: ElasticSwitch.trackWidth,
              height: ElasticSwitch.trackHeight,
              decoration: ShapeDecoration(
                color: _isEnabled ? trackColor : trackColor.withValues(alpha: 0.4),
                shape: const StadiumBorder(),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: leftOffset.clamp(
                      ElasticSwitch._inset,
                      ElasticSwitch.trackWidth - ElasticSwitch._inset - currentThumbWidth,
                    ),
                    child: Container(
                      width: currentThumbWidth,
                      height: ElasticSwitch._thumbSize,
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: const StadiumBorder(),
                        shadows: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.18),
                            blurRadius: 4,
                            offset: const Offset(0, 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
