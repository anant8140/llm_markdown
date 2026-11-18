import 'package:flutter/widgets.dart';

enum MarkdownIconKind { copy, check, box, checkedBox, chevron }

class MarkdownIcon extends StatelessWidget {
  const MarkdownIcon(
    this.kind, {
    super.key,
    required this.color,
    this.accentColor,
    this.size = 16,
  });

  final MarkdownIconKind kind;

  final Color color;

  final Color? accentColor;

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _IconPainter(kind, color, accentColor ?? color),
    ),
  );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.kind, this.color, this.accent);

  final MarkdownIconKind kind;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s / 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path check(double inset) => Path()
      ..moveTo(s * (0.22 + inset), s * 0.52)
      ..lineTo(s * 0.43, s * (0.72 - inset))
      ..lineTo(s * (0.80 - inset), s * (0.30 + inset));

    switch (kind) {
      case MarkdownIconKind.copy:
        final radius = Radius.circular(s * 0.12);
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(s * 0.32, s * 0.30, s * 0.52, s * 0.58),
              radius,
            ),
            stroke,
          )
          ..drawPath(
            Path()
              ..moveTo(s * 0.18, s * 0.66)
              ..lineTo(s * 0.18, s * 0.24)
              ..quadraticBezierTo(s * 0.18, s * 0.12, s * 0.30, s * 0.12)
              ..lineTo(s * 0.62, s * 0.12),
            stroke,
          );
      case MarkdownIconKind.check:
        canvas.drawPath(check(0), stroke);
      case MarkdownIconKind.chevron:
        canvas.drawPath(
          Path()
            ..moveTo(s * 0.38, s * 0.24)
            ..lineTo(s * 0.64, s * 0.5)
            ..lineTo(s * 0.38, s * 0.76),
          stroke,
        );
      case MarkdownIconKind.box || MarkdownIconKind.checkedBox:
        final box = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.12, s * 0.12, s * 0.76, s * 0.76),
          Radius.circular(s * 0.14),
        );
        if (kind == MarkdownIconKind.box) {
          canvas.drawRRect(box, stroke);
        } else {
          canvas
            ..drawRRect(box, Paint()..color = accent)
            ..drawPath(
              check(0.06),
              stroke
                ..color = accent.computeLuminance() > 0.5
                    ? const Color(0xFF000000)
                    : const Color(0xFFFFFFFF),
            );
        }
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.kind != kind || old.color != color || old.accent != accent;
}
