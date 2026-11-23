import 'package:flutter/widgets.dart';

/// A tappable, focusable button for screen readers and keyboards.
class PlainButton extends StatelessWidget {
  /// A button named [label] that shows [child].
  const PlainButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected,
  });

  /// What screen readers say.
  final String label;

  /// Called on a tap or Enter; `null` turns the button off.
  final VoidCallback? onTap;

  /// Whether it is the chosen one of a group, for screen readers.
  final bool? selected;

  /// What the button looks like.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return Semantics(
      container: true,
      button: true,
      enabled: tap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: tap,
      child: FocusableActionDetector(
        enabled: tap != null,
        mouseCursor: tap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              tap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: child,
        ),
      ),
    );
  }
}

/// The small drawings on the buttons.
enum PlainIcon {
  /// An arrow pointing up.
  send,

  /// A square.
  stop,

  /// A plus sign.
  add,

  /// A microphone.
  mic,

  /// A cross.
  close,
}

/// Paints a [PlainIcon] in the middle of its box.
class PlainIconPainter extends CustomPainter {
  /// A painter of [icon] in [color].
  const PlainIconPainter({required this.icon, required this.color});

  /// What to draw.
  final PlainIcon icon;

  /// The color of the lines.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..strokeWidth = icon == PlainIcon.close ? 1.6 : 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    switch (icon) {
      case PlainIcon.stop:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 12, height: 12),
            const Radius.circular(2),
          ),
          Paint()..color = color,
        );
      case PlainIcon.send:
        canvas
          ..drawLine(center.translate(0, 7), center.translate(0, -7), paint)
          ..drawPath(
            Path()
              ..moveTo(center.dx - 6, center.dy - 1)
              ..lineTo(center.dx, center.dy - 7)
              ..lineTo(center.dx + 6, center.dy - 1),
            paint,
          );
      case PlainIcon.add:
        canvas
          ..drawLine(center.translate(0, 7), center.translate(0, -7), paint)
          ..drawLine(center.translate(-7, 0), center.translate(7, 0), paint);
      case PlainIcon.close:
        canvas
          ..drawLine(center.translate(-4, -4), center.translate(4, 4), paint)
          ..drawLine(center.translate(-4, 4), center.translate(4, -4), paint);
      case PlainIcon.mic:
        paint.strokeWidth = 1.8;
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: center.translate(0, -3),
                width: 6,
                height: 11,
              ),
              const Radius.circular(3),
            ),
            paint,
          )
          ..drawArc(
            Rect.fromCenter(
              center: center.translate(0, -2),
              width: 12,
              height: 12,
            ),
            0,
            3.14159,
            false,
            paint,
          )
          ..drawLine(center.translate(0, 4), center.translate(0, 8), paint);
    }
  }

  @override
  bool shouldRepaint(PlainIconPainter old) =>
      old.icon != icon || old.color != color;
}
