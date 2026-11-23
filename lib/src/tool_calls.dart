import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'renderer.dart' show StreamingCursor, StreamingCursorStyle;

/// Builds the line shown for one tool call, in place of the built-in one.
typedef MarkdownToolCallBuilder =
    Widget Function(BuildContext context, MarkdownToolCall call);

String defaultToolCallLabel(String name, bool done) {
  final words = name.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  final shown = words.isEmpty ? 'a tool' : words;
  return done ? 'Used $shown' : 'Using $shown…';
}

// One line per tool call: dots that light up while it runs, then a tick.
class ToolCallLine extends StatelessWidget {
  const ToolCallLine({
    super.key,
    required this.label,
    required this.done,
    required this.color,
    required this.textStyle,
  });

  final String label;
  final bool done;
  final Color color;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final size = textStyle.fontSize ?? 14;
    return Semantics(
      // stays a live region, so the change to done is read out too
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            Text('\u2713', style: textStyle.copyWith(color: color))
          else
            StreamingCursor(
              color: color,
              fontSize: size * 0.8,
              style: StreamingCursorStyle.dots,
            ),
          SizedBox(width: size * 0.4),
          Flexible(
            child: Text(
              label,
              style: textStyle.copyWith(
                color: textStyle.color?.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
