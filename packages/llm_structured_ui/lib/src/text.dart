import 'package:flutter/widgets.dart';
import 'package:llm_markdown/llm_markdown.dart';

import 'indicators.dart';
import 'style.dart';
import 'value.dart';

/// Shows a string field, with a blinking cursor while it is still being
/// written.
///
/// A number or bool is shown as its text. A value that is missing, a map
/// or a list shows no text.
class StructuredText extends StatelessWidget {
  /// Shows [value]. With [markdown], the text is drawn as Markdown.
  const StructuredText(
    this.value, {
    super.key,
    this.markdown = false,
    this.showCursor = true,
    this.textStyle,
    this.style,
  });

  /// The value to show.
  final StructuredValue value;

  /// Whether the text is Markdown; it is then drawn by `StreamingMarkdown`
  /// from the `llm_markdown` package.
  final bool markdown;

  /// Whether a cursor follows the text while the value is pending.
  final bool showCursor;

  /// The text style; defaults to [StructuredStyle.textStyle].
  final TextStyle? textStyle;

  /// The look; defaults to [StructuredStyle.of] the context.
  final StructuredStyle? style;

  /// The text shown for [value]: a string as it is, a number or bool as
  /// text, and nothing for anything else.
  static String textOf(StructuredValue value) {
    final raw = value.raw;
    return switch (raw) {
      String() => raw,
      num() || bool() => '$raw',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? StructuredStyle.of(context);
    final textStyle = this.textStyle ?? style.textStyle;
    final text = textOf(value);
    final pending = value.isPending;
    if (markdown) {
      return DefaultTextStyle.merge(
        style: textStyle,
        child: StreamingMarkdown.text(
          text,
          isComplete: !pending,
          showCursor: showCursor,
          announceWhenDone: false,
        ),
      );
    }
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          if (pending && showCursor)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: StructuredCursor(
                height: textStyle.fontSize ?? 14,
                color: style.cursorColor,
              ),
            ),
        ],
      ),
      style: textStyle,
    );
  }
}
