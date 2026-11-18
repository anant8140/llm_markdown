import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'icons.dart';

export 'thinking_split.dart';

/// Returns the title of the thinking section.
///
/// [duration] is how long the model thought, or null while it is still
/// thinking or when the time is not known.
typedef ThinkingLabelBuilder =
    String Function(bool thinkingDone, Duration? duration);

String defaultThinkingLabel(bool done, Duration? duration) {
  if (!done) return 'Thinking';
  if (duration == null) return 'Thoughts';
  return 'Thought for ${math.max(1, duration.inSeconds)}s';
}

class ThinkingSection extends StatefulWidget {
  const ThinkingSection({
    super.key,
    required this.label,
    required this.done,
    required this.color,
    required this.textStyle,
    required this.initiallyExpanded,
    required this.child,
  });

  final String label;
  final bool done;
  final Color color;
  final TextStyle textStyle;
  final bool initiallyExpanded;
  final Widget child;

  @override
  State<ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<ThinkingSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncDots();
  }

  @override
  void didUpdateWidget(ThinkingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDots();
  }

  void _syncDots() {
    if (widget.done || _still) {
      _dots.stop();
    } else if (!_dots.isAnimating) {
      _dots.repeat();
    }
  }

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final headerStyle = widget.textStyle.copyWith(color: widget.color);
    final header = Semantics(
      button: true,
      expanded: _expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _dots,
                  builder: (context, _) => Text(
                    widget.done
                        ? widget.label
                        : _still
                        ? '${widget.label}...'
                        : '${widget.label}${'.' * (1 + (_dots.value * 3).floor() % 3)}',
                    style: headerStyle,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: MarkdownIcon(
                    MarkdownIconKind.chevron,
                    color: widget.color,
                    size: (widget.textStyle.fontSize ?? 14) * 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(alignment: AlignmentDirectional.centerStart, child: header),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _expanded
              ? Container(
                  margin: const EdgeInsetsDirectional.only(top: 6, start: 2),
                  padding: const EdgeInsetsDirectional.only(start: 12),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                        color: widget.color.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Opacity(opacity: 0.75, child: widget.child),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
