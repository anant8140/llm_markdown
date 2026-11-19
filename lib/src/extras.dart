import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'icons.dart';
import 'package:llm_markdown_parser/llm_markdown_parser.dart';
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

/// Builds the jump button of [JumpToLatest]; call [jump] to scroll to the
/// end.
typedef JumpToLatestBuilder =
    Widget Function(BuildContext context, VoidCallback jump);

/// Shows a button while the user has scrolled away from the end of a chat,
/// for example a "↓ New messages" chip in a `Stack` over the list.
///
/// Give it the same [controller] as `StreamingMarkdown.autoScrollController`.
/// Once the list is back at the end, following new text resumes.
class JumpToLatest extends StatefulWidget {
  /// Creates a jump-to-latest button.
  const JumpToLatest({
    super.key,
    required this.controller,
    required this.builder,
    this.content,
    this.threshold = 48,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeOut,
  });

  /// The scroll controller of the chat list.
  final ScrollController controller;

  /// Builds the button.
  final JumpToLatestBuilder builder;

  /// Something that changes when text arrives, such as the
  /// `StreamingMarkdownController`, so the button also shows when new text
  /// grows the list below the screen.
  final Listenable? content;

  /// How far from the end, in pixels, still counts as at the end.
  final double threshold;

  /// How long the jump takes; zero jumps at once.
  final Duration duration;

  /// The curve of the jump.
  final Curve curve;

  @override
  State<JumpToLatest> createState() => _JumpToLatestState();
}

class _JumpToLatestState extends State<JumpToLatest> {
  bool _away = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _listen(widget);
    _schedule();
  }

  @override
  void didUpdateWidget(JumpToLatest oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.content != widget.content) {
      _unlisten(oldWidget);
      _listen(widget);
      _schedule();
    }
  }

  @override
  void dispose() {
    _unlisten(widget);
    super.dispose();
  }

  void _listen(JumpToLatest widget) {
    widget.controller.addListener(_schedule);
    widget.content?.addListener(_schedule);
  }

  void _unlisten(JumpToLatest widget) {
    widget.controller.removeListener(_schedule);
    widget.content?.removeListener(_schedule);
  }

  // after layout, when the scroll extent is known
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final controller = widget.controller;
      var away = false;
      if (controller.positions.length == 1) {
        final position = controller.position;
        away =
            position.hasContentDimensions &&
            position.maxScrollExtent - position.pixels > widget.threshold;
      }
      if (away != _away) setState(() => _away = away);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _jump() {
    final controller = widget.controller;
    if (controller.positions.length != 1) return;
    final end = controller.position.maxScrollExtent;
    if (widget.duration == Duration.zero) {
      controller.jumpTo(end);
    } else {
      unawaited(
        controller.animateTo(
          end,
          duration: widget.duration,
          curve: widget.curve,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) =>
      _away ? widget.builder(context, _jump) : const SizedBox.shrink();
}
