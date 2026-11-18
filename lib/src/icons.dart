import 'package:flutter/widgets.dart';

/// The small icons this package draws itself, so it needs no icon font and
/// no design library.
enum MarkdownIconKind {
  /// Two overlapping sheets, for the copy button.
  copy,

  /// A check mark, shown after copying.
  check,

  /// An empty task-list box.
  box,

  /// A checked task-list box.
  checkedBox,
}

/// Draws one [MarkdownIconKind] in a square of [size].
class MarkdownIcon extends StatelessWidget {
  /// Creates an icon.
  const MarkdownIcon(
    this.kind, {
    super.key,
    required this.color,
    this.accentColor,
    this.size = 16,
  });

  /// Which icon to draw.
  final MarkdownIconKind kind;

  /// The line color.
  final Color color;

  /// The fill of a checked box; defaults to [color].
  final Color? accentColor;

  /// The width and height.
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
