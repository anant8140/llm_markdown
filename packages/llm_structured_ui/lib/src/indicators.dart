import 'package:flutter/widgets.dart';

import 'style.dart';

// Runs a repeating animation while mounted, unless the platform asks for
// animations to be off; then the value stays at 1.
mixin _Pulse<T extends StatefulWidget> on State<T>, TickerProvider {
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: pulseDuration,
    value: 1,
  );

  Duration get pulseDuration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final off = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (off) {
      pulse
        ..stop()
        ..value = 1;
    } else if (!pulse.isAnimating) {
      pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }
}

/// The blinking cursor shown after text that is still arriving.
///
/// It is left out of the semantics tree, and it does not blink when the
/// platform asks for animations to be off. It animates only while it is in
/// the tree, so show it only while the value is pending.
class StructuredCursor extends StatefulWidget {
  /// A cursor [height] tall; [color] defaults to the style's cursor color.
  const StructuredCursor({super.key, this.height = 14, this.color});

  /// The height of the cursor; use the font size of the text beside it.
  final double height;

  /// The color; defaults to [StructuredStyle.cursorColor].
  final Color? color;

  @override
  State<StructuredCursor> createState() => _StructuredCursorState();
}

class _StructuredCursorState extends State<StructuredCursor>
    with SingleTickerProviderStateMixin, _Pulse {
  @override
  Duration get pulseDuration => const Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? StructuredStyle.of(context).cursorColor;
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: pulse,
        child: Container(
          width: widget.height * 0.5,
          height: widget.height,
          margin: const EdgeInsetsDirectional.only(start: 2),
          color: color,
        ),
      ),
    );
  }
}

/// A placeholder line for a value that has not arrived yet. Its opacity
/// moves up and down slowly.
///
/// It is left out of the semantics tree, and it stays still when the
/// platform asks for animations to be off. It animates only while it is in
/// the tree, so show it only while the value is awaited.
class StructuredPlaceholder extends StatefulWidget {
  /// A line [width] wide (at most the space there is) and [height] tall.
  const StructuredPlaceholder({
    super.key,
    this.width = 120,
    this.height = 12,
    this.color,
  });

  /// The width of the line.
  final double width;

  /// The height of the line.
  final double height;

  /// The color; defaults to [StructuredStyle.placeholderColor].
  final Color? color;

  @override
  State<StructuredPlaceholder> createState() => _StructuredPlaceholderState();
}

class _StructuredPlaceholderState extends State<StructuredPlaceholder>
    with SingleTickerProviderStateMixin, _Pulse {
  static final _fade = Tween<double>(begin: 0.4, end: 1);

  @override
  Duration get pulseDuration => const Duration(milliseconds: 800);

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? StructuredStyle.of(context).placeholderColor;
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: _fade.animate(pulse),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.width),
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(widget.height / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
