import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({super.key, this.size = 20.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        'assets/images/Google__G__logo.svg',
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => CustomPaint(
          size: Size(size, size),
          painter: _GoogleLogoPainter(),
        ),
        placeholderBuilder: (context) => CustomPaint(
          size: Size(size, size),
          painter: _GoogleLogoPainter(),
        ),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);
    final double strokeWidth = size.width * 0.22;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Blue arc (Right)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.4, 1.25, false, paint);

    // Green arc (Bottom)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.85, 1.35, false, paint);

    // Yellow arc (Left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.2, 0.95, false, paint);

    // Red arc (Top)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.15, 1.5, false, paint);

    // Blue horizontal bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTRB(radius - 1, radius - strokeWidth / 2, radius + strokeWidth * 1.1, radius + strokeWidth / 2),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
