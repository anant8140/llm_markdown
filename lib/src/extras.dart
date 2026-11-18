import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'icons.dart';
import 'plain_text.dart';
import 'style.dart';

/// Grey lines that shimmer while the first words of a reply are on the way.
///
/// Pass it as `StreamingMarkdown.placeholder`.
class MarkdownShimmer extends StatefulWidget {
  /// Creates a shimmer of [lines] lines.
  const MarkdownShimmer({super.key, this.lines = 3, this.color});

  /// How many lines to draw; the last one is shorter.
  final int lines;

  /// The line color; defaults to a tint of the text color.
  final Color? color;

  @override
  State<MarkdownShimmer> createState() => _MarkdownShimmerState();
}

class _MarkdownShimmerState extends State<MarkdownShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      unawaited(_shine.repeat());
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = DefaultTextStyle.of(context).style;
    final base =
        widget.color ??
        (text.color ?? const Color(0xFF808080)).withValues(alpha: 0.12);
    final height = (text.fontSize ?? 14) * 0.9;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _shine,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.lines; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: FractionallySizedBox(
                  widthFactor: i == widget.lines - 1 ? 0.6 : 1,
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height / 2),
                      gradient: LinearGradient(
                        begin: Alignment(-1 + 3 * _shine.value - 1, 0),
                        end: Alignment(-1 + 3 * _shine.value, 0),
                        colors: [
                          base,
                          base.withValues(alpha: base.a * 2.2),
                          base,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small "Copy" button that copies the reply of [controller].
///
/// With [plainText] it copies the reply without Markdown marks, using
/// [markdownToPlainText]; otherwise it copies the Markdown source.
class CopyReplyButton extends StatefulWidget {
  /// Creates a copy button for [controller].
  const CopyReplyButton({
    super.key,
    required this.controller,
    this.plainText = false,
    this.label,
    this.style,
  });

  /// The reply to copy.
  final StreamingMarkdownController controller;

  /// Whether to copy plain text instead of Markdown.
  final bool plainText;

  /// The button label; defaults to the platform's "Copy".
  final String? label;

  /// The look; defaults to [StreamingMarkdownStyle.of] the context.
  final StreamingMarkdownStyle? style;

  @override
  State<CopyReplyButton> createState() => _CopyReplyButtonState();
}

class _CopyReplyButtonState extends State<CopyReplyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final text = widget.plainText
        ? markdownToPlainText(widget.controller.text)
        : widget.controller.text;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? StreamingMarkdownStyle.of(context);
    final header = style.codeBlockHeaderStyle;
    final label =
        widget.label ??
        Localizations.of<WidgetsLocalizations>(
          context,
          WidgetsLocalizations,
        )?.copyButtonLabel ??
        'Copy';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _copy,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MarkdownIcon(
                  _copied ? MarkdownIconKind.check : MarkdownIconKind.copy,
                  color: header.color ?? const Color(0xFF808080),
                ),
                const SizedBox(width: 4),
                Text(label, style: header),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
