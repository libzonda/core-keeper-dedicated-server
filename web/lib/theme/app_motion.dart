import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Physical Motion & Spring System (Damped Harmonic Oscillators)
abstract final class AppMotion {
  // Physical Spring Models
  static final SpringDescription dropletSpring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 165.0,
    ratio: 0.8,
  );

  static final SpringDescription pressSpring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 311.0,
    ratio: 0.593,
  );

  static final SpringDescription followSpring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 1024.0,
    ratio: 0.9,
  );

  static final SpringDescription travelSpring = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 400),
    bounce: 0.15,
  );

  static final SpringDescription alertSpring = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 275),
    bounce: 0.0,
  );

  // Standard Durations
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
  static const Duration tabFade = Duration(milliseconds: 220);
  static const Duration alertDuration = Duration(milliseconds: 404);

  // Motion Curves
  static const Curve easeOutCubic = Curves.easeOutCubic;
  static const Curve easeOutBack = Curves.easeOutBack;
  static const Curve easeInOut = Curves.easeInOut;
  static const Curve standard = Curves.easeInOutCubic;
}

/// Plays [spring] over the first [seconds] of an animation, easing out the
/// remaining residual so the curve still ends exactly at 1.0.
class SpringCurve extends Curve {
  final double seconds;
  final SpringSimulation _simulation;
  late final double _residual = 1.0 - _simulation.x(seconds);

  SpringCurve(SpringDescription spring, {this.seconds = 0.4})
      : _simulation = SpringSimulation(spring, 0, 1, 0);

  @override
  double transformInternal(double t) {
    return _simulation.x(t * seconds) + _residual * t;
  }
}
