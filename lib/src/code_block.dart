import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import 'fade.dart';
import 'icons.dart';
import 'style.dart';

Highlight? _highlighter;

Highlight get _sharedHighlighter =>
    _highlighter ??= Highlight()..registerLanguages(builtinAllLanguages);

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
    // some grammars throw on odd input, fall back to plain text
    return null;
  }
}

class CodeBlockView extends StatefulWidget {
  const CodeBlockView({
    super.key,
    required this.code,
    required this.language,
    required this.style,
    required this.highlight,
    this.trailing,
    this.fadeLength = 0,
  });

  final int fadeLength;

  final String code;

  final String? language;

  final StreamingMarkdownStyle style;

  final bool highlight;

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
        ...(_highlighted == null
            ? fadeTail(
                [TextSpan(text: widget.code)],
                style.codeBlockTextStyle,
                widget.fadeLength,
              )
            : [_highlighted!]),
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
