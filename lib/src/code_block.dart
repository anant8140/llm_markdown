import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import 'icons.dart';
import 'style.dart';

Highlight? _highlighter;

Highlight get _sharedHighlighter =>
    _highlighter ??= Highlight()..registerLanguages(builtinAllLanguages);

/// Returns [code] as highlighted spans, or null when [language] is unknown.
TextSpan? highlightCode(
  String code,
  String? language,
  TextStyle base,
  Map<String, TextStyle> theme,
) {
  if (language == null || language.isEmpty) return null;
  final highlighter = _sharedHighlighter;
  final name = language.toLowerCase();
  if (highlighter.getLanguage(name) == null) return null;
  try {
    final result = highlighter.highlight(code: code, language: name);
    final renderer = TextSpanRenderer(base, theme);
    result.render(renderer);
    return renderer.span;
  } on Object {
    // The highlighter is a port of highlight.js; a grammar bug must not
    // break the reply, so plain text is shown instead.
    return null;
  }
}

/// A fenced code block with its language and a copy button.
class CodeBlockView extends StatefulWidget {
  /// Creates a code block view.
  const CodeBlockView({
    super.key,
    required this.code,
    required this.language,
    required this.style,
    required this.highlight,
    this.trailing,
  });

  /// The code, without the fences.
  final String code;

  /// The language from the info string, such as `dart`.
  final String? language;

  /// The style to draw with.
  final StreamingMarkdownStyle style;

  /// Whether to highlight the code; false while the block still grows.
  final bool highlight;

  /// A span shown after the code, used for the streaming cursor.
  final InlineSpan? trailing;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  TextSpan? _highlighted;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _highlight();
  }

  @override
  void didUpdateWidget(CodeBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language ||
        oldWidget.highlight != widget.highlight ||
        oldWidget.style != widget.style) {
      _highlight();
    }
  }

  void _highlight() {
    _highlighted = widget.highlight
        ? highlightCode(
            widget.code,
            widget.language,
            widget.style.codeBlockTextStyle,
            widget.style.codeTheme,
          )
        : null;
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final header = style.codeBlockHeaderStyle;
    final copyLabel =
        Localizations.of<WidgetsLocalizations>(
          context,
          WidgetsLocalizations,
        )?.copyButtonLabel ??
        'Copy';
    final code = TextSpan(
      style: style.codeBlockTextStyle,
      children: [
        _highlighted ?? TextSpan(text: widget.code),
        if (widget.trailing != null) widget.trailing!,
      ],
    );
    return DecoratedBox(
      decoration: style.codeBlockDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language ?? 'code',
                    style: header,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Semantics(
                  button: true,
                  label: copyLabel,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _copy,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MarkdownIcon(
                              _copied
                                  ? MarkdownIconKind.check
                                  : MarkdownIconKind.copy,
                              color: header.color ?? const Color(0xFF808080),
                            ),
                            const SizedBox(width: 4),
                            Text(copyLabel, style: header),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Text.rich(code, softWrap: false),
          ),
        ],
      ),
    );
  }
}
