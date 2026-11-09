import 'package:flutter/material.dart';

class GithubIcon extends StatelessWidget {
  final double size;
  final Color color;

  const GithubIcon({
    super.key,
    this.size = 18.0,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GithubIconPainter(color: color),
      ),
    );
  }
}

class _GithubIconPainter extends CustomPainter {
  final Color color;

  _GithubIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final path = Path();
    path.moveTo(12.0, 2.0);
    path.cubicTo(6.477, 2.0, 2.0, 6.484, 2.0, 12.017);
    path.cubicTo(2.0, 16.442, 4.865, 20.197, 8.839, 21.521);
    path.cubicTo(9.339, 21.613, 9.521, 21.304, 9.521, 21.038);
    path.cubicTo(9.521, 20.801, 9.513, 20.17, 9.508, 19.335);
    path.cubicTo(6.726, 19.94, 6.139, 17.992, 6.139, 17.992);
    path.cubicTo(5.685, 16.834, 5.029, 16.526, 5.029, 16.526);
    path.cubicTo(4.121, 15.906, 5.098, 15.918, 5.098, 15.918);
    path.cubicTo(6.101, 15.988, 6.628, 16.95, 6.628, 16.95);
    path.cubicTo(7.52, 18.48, 8.969, 18.038, 9.538, 17.782);
    path.cubicTo(9.63, 17.135, 9.888, 16.694, 10.174, 16.446);
    path.cubicTo(7.954, 16.193, 5.619, 15.333, 5.619, 11.495);
    path.cubicTo(5.619, 10.402, 6.009, 9.507, 6.648, 8.807);
    path.cubicTo(6.545, 8.554, 6.202, 7.535, 6.746, 6.157);
    path.cubicTo(6.746, 6.157, 7.586, 5.887, 9.496, 7.183);
    path.cubicTo(10.294, 6.961, 11.149, 6.85, 12.0, 6.844);
    path.cubicTo(12.85, 6.848, 13.705, 6.961, 14.504, 7.183);
    path.cubicTo(16.414, 5.887, 17.252, 6.157, 17.252, 6.157);
    path.cubicTo(17.798, 7.535, 17.454, 8.554, 17.352, 8.807);
    path.cubicTo(17.992, 9.507, 18.38, 10.402, 18.38, 11.495);
    path.cubicTo(18.38, 15.343, 16.041, 16.19, 13.814, 16.438);
    path.cubicTo(14.173, 16.747, 14.492, 17.358, 14.492, 18.293);
    path.cubicTo(14.492, 19.631, 14.48, 20.712, 14.48, 21.04);
    path.cubicTo(14.48, 21.308, 14.66, 21.62, 15.168, 21.522);
    path.cubicTo(19.141, 20.194, 22.0, 16.442, 22.0, 12.017);
    path.cubicTo(22.0, 6.484, 17.522, 2.0, 12.0, 2.0);
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GithubIconPainter oldDelegate) => oldDelegate.color != color;
}

