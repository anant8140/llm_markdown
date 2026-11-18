import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'code_block.dart';
import 'direction.dart';
import 'fade.dart';
import 'icons.dart';
import 'math.dart';
import 'safety.dart';
import 'style.dart';

/// Builds a widget for an image, given its address and alternative text.
typedef MarkdownImageBuilder =
    Widget Function(BuildContext context, Uri uri, String? alt);

/// Builds a widget for a fenced code block, or returns null to use the
/// default code block.
///
/// [isComplete] is false while the block's closing fence has not arrived.
typedef MarkdownCodeBlockBuilder =
    Widget? Function(
      BuildContext context,
      String code,
      String? language,
      bool isComplete,
    );

/// Builds a widget for a LaTeX formula, for example with `Math.tex` from
/// `flutter_math_fork`.
///
/// [display] is true for block formulas (`$$...$$`, `\[...\]`) and false
/// for inline ones (`$...$`, `\(...\)`). Formulas that are still
/// arriving are not passed to the builder; their source is shown instead.
typedef MarkdownMathBuilder =
    Widget Function(BuildContext context, String tex, bool display);

/// The shape of the cursor shown while text arrives.
enum StreamingCursorStyle {
  /// A solid block, like a terminal.
  block,

  /// A thin vertical bar.
  bar,

  /// A line under where the next letter goes.
  underline,

  /// Three dots that light up in turn.
  dots,
}

class RenderSettings {
  StreamingMarkdownStyle? style;

  ValueChanged<String>? onLinkTap;

  MarkdownImageBuilder? imageBuilder;

  MarkdownCodeBlockBuilder? codeBlockBuilder;

  bool highlightCode = true;

  bool newlinesAsBreaks = false;

  MarkdownMathBuilder? mathBuilder;

  bool showCursor = true;

  int fadeLength = 0;

  StreamingCursorStyle cursorStyle = StreamingCursorStyle.block;

  bool detectTextDirection = true;

  Set<String> linkSchemes = defaultLinkSchemes;

  Set<String> imageSchemes = defaultImageSchemes;
}

const Set<String> _textContainers = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'pre',
  'th',
  'td',
  blockMathTag,
};

const Set<String> _blockTags = {
  blockMathTag,
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'pre',
  'blockquote',
  'ul',
  'ol',
  'li',
  'hr',
  'table',
  'thead',
  'tbody',
  'tr',
  'section',
  'div',
};

bool _isInline(md.Node node) =>
    node is! md.Element || !_blockTags.contains(node.tag);

md.Element? findCursorTarget(List<md.Node> nodes) {
  for (final node in nodes.reversed) {
    if (node is! md.Element) return null;
    if (_textContainers.contains(node.tag)) return node;
    final children = node.children ?? const <md.Node>[];
    final inner = findCursorTarget(children);
    if (inner != null) return inner;
    if (node.tag == 'li' && children.isNotEmpty && _isInline(children.last)) {
      return node;
    }
    if (node.tag == 'hr' || node.tag == 'table') return null;
  }
  return null;
}

class MarkdownBlockView extends StatefulWidget {
  const MarkdownBlockView({
    super.key,
    required this.nodes,
    required this.settings,
    required this.isComplete,
    this.cursorTarget,
    this.debugId,
  });

  final List<md.Node> nodes;

  final RenderSettings settings;

  final bool isComplete;

  final md.Element? cursorTarget;

  final int? debugId;

  @visibleForTesting
  static final Map<int, int> debugBuildCounts = {};

  @override
  State<MarkdownBlockView> createState() => _MarkdownBlockViewState();
}

class _RecognizerPool {
  final List<TapGestureRecognizer> _all = [];
  int _used = 0;

  TapGestureRecognizer take() {
    if (_used == _all.length) _all.add(TapGestureRecognizer());
    return _all[_used++];
  }

  void begin() => _used = 0;

  void end() {
    while (_all.length > _used) {
      _all.removeLast().dispose();
    }
  }

  void dispose() {
    _used = 0;
    end();
  }
}

class _MarkdownBlockViewState extends State<MarkdownBlockView> {
  final _RecognizerPool _recognizers = _RecognizerPool();

  @override
  void dispose() {
    _recognizers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(() {
      final id = widget.debugId;
      if (id != null) {
        MarkdownBlockView.debugBuildCounts[id] =
            (MarkdownBlockView.debugBuildCounts[id] ?? 0) + 1;
      }
      return true;
    }());
    _recognizers.begin();
    final result = _Builder(
      context: context,
      settings: widget.settings,
      style: widget.settings.style!,
      recognizers: _recognizers,
      cursorTarget: widget.cursorTarget,
      isComplete: widget.isComplete,
    ).blocks(widget.nodes);
    _recognizers.end();
    return result;
  }
}

class StreamingCursor extends StatefulWidget {
  const StreamingCursor({
    super.key,
    required this.color,
    this.fontSize = 14,
    this.style = StreamingCursorStyle.block,
  });

  final Color color;

  final double fontSize;

  final StreamingCursorStyle style;

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 530),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _blink
        ..stop()
        ..value = 1;
    } else if (!_blink.isAnimating) {
      unawaited(_blink.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.fontSize;
    final color = widget.color;
    if (widget.style == StreamingCursorStyle.dots) {
      return ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _blink,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: size * 0.28,
                  height: size * 0.28,
                  margin: EdgeInsetsDirectional.only(start: size * 0.12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: _dotAlpha(i, _blink.value)),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final (width, height, alignment) = switch (widget.style) {
      StreamingCursorStyle.bar => (size * 0.12, size * 1.15, Alignment.center),
      StreamingCursorStyle.underline => (
        size * 0.6,
        size * 0.12,
        Alignment.bottomCenter,
      ),
      _ => (size * 0.5, size * 1.05, Alignment.center),
    };
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.25).animate(_blink),
        child: SizedBox(
          height: size * 1.15,
          child: Align(
            alignment: alignment,
            widthFactor: 1,
            child: Container(
              width: width,
              height: height,
              margin: const EdgeInsetsDirectional.only(start: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // each dot is brightest in its own third of the blink cycle
  double _dotAlpha(int index, double value) {
    final phase = (value * 3 - index).abs();
    return phase < 1 ? 1 - phase * 0.7 : 0.3;
  }
}

class _Builder {
  _Builder({
    required this.context,
    required this.settings,
    required this.style,
    required this.recognizers,
    required this.cursorTarget,
    required this.isComplete,
  });

  final BuildContext context;
  final RenderSettings settings;
  final StreamingMarkdownStyle style;
  final _RecognizerPool recognizers;
  final md.Element? cursorTarget;
  final bool isComplete;
  int _listDepth = 0;

  InlineSpan _cursor(TextStyle textStyle) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: StreamingCursor(
      color: style.accentColor,
      fontSize: textStyle.fontSize ?? 14,
      style: settings.cursorStyle,
    ),
  );

  Widget blocks(List<md.Node> nodes, {md.Element? parent}) {
    final children = <Widget>[];
    final pending = <md.Node>[];

    void flushInline({required bool isLast}) {
      if (pending.isEmpty) return;
      final cursor =
          isLast && parent != null && identical(parent, cursorTarget);
      final inline = List<md.Node>.of(pending);
      pending.clear();
      if (inline.every((n) => n is md.Text && n.text.trim().isEmpty)) return;
      children.add(_paragraph(inline, style.textStyle, cursor: cursor));
    }

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (_isInline(node)) {
        pending.add(node);
        continue;
      }
      flushInline(isLast: false);
      final widget = _block(node as md.Element);
      if (widget != null) children.add(widget);
    }
    flushInline(isLast: true);

    if (children.length == 1) return children.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: style.blockSpacing),
          children[i],
        ],
      ],
    );
  }

  Widget? _block(md.Element element) {
    switch (element.tag) {
      case blockMathTag:
        return _mathBlock(
          element.textContent,
          closed: element.attributes['closed'] == 'true',
          target: identical(element, cursorTarget),
        );
      case 'p':
        final only = element.children?.length == 1
            ? element.children!.single
            : null;
        if (only is md.Element &&
            only.tag == inlineMathTag &&
            only.attributes['display'] == 'true') {
          return _mathBlock(only.textContent, closed: true, target: false);
        }
        return _paragraph(
          element.children ?? const [],
          style.textStyle,
          cursor: identical(element, cursorTarget),
        );
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(element.tag.substring(1));
        return Semantics(
          header: true,
          child: _paragraph(
            element.children ?? const [],
            style.headingStyles[level - 1],
            cursor: identical(element, cursorTarget),
          ),
        );
      case 'blockquote':
        return _directed(
          element.textContent,
          DecoratedBox(
            decoration: style.blockquoteDecoration,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 14),
              child: blocks(element.children ?? const [], parent: element),
            ),
          ),
        );
      case 'ul' || 'ol':
        return _directed(element.textContent, _list(element));
      case 'pre':
        return _codeBlock(element);
      case 'hr':
        return Container(height: 1, color: style.dividerColor);
      case 'table':
        return _directed(element.textContent, _table(element));
      default:
        return blocks(element.children ?? const [], parent: element);
    }
  }

  Widget _paragraph(
    List<md.Node> nodes,
    TextStyle textStyle, {
    required bool cursor,
  }) {
    final spans = <InlineSpan>[
      for (final node in nodes) ..._inline(node, textStyle, null),
    ];
    _trimRawHtml(spans);
    return Text.rich(
      TextSpan(
        style: textStyle,
        children: cursor ? _streamingTail(spans, textStyle) : spans,
      ),
      textDirection: _direction(nodes.map((n) => n.textContent).join()),
    );
  }

  TextDirection? _direction(String text) =>
      settings.detectTextDirection ? detectTextDirection(text) : null;

  Widget _directed(String text, Widget child) {
    final direction = _direction(text);
    return direction == null
        ? child
        : Directionality(textDirection: direction, child: child);
  }

  // Screen readers get the TeX source rather than the drawn glyphs.
  Widget _mathSemantics(String tex, Widget child) => Semantics(
    label: tex,
    child: ExcludeSemantics(child: child),
  );

  // Fade-in and cursor at the end of the text that is still arriving.
  List<InlineSpan> _streamingTail(List<InlineSpan> spans, TextStyle style) => [
    ...fadeTail(spans, style, settings.fadeLength),
    if (settings.showCursor) _cursor(style),
  ];

  Widget _mathBlock(String tex, {required bool closed, required bool target}) {
    final builder = settings.mathBuilder;
    if (closed && builder != null) {
      return Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _mathSemantics(tex, builder(context, tex, true)),
        ),
      );
    }
    final source = style.codeBlockTextStyle.copyWith(
      color: style.codeBlockHeaderStyle.color,
    );
    return Center(
      child: Text.rich(
        TextSpan(
          style: source,
          children: target
              ? _streamingTail([TextSpan(text: tex)], source)
              : [TextSpan(text: tex)],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _trimRawHtml(List<InlineSpan> spans) {
    if (spans.length != 1) return;
    final span = spans.single;
    if (span is TextSpan && span.text != null && span.children == null) {
      spans[0] = TextSpan(
        text: span.text!.trim(),
        style: span.style,
        recognizer: span.recognizer,
      );
    }
  }

  List<InlineSpan> _inline(
    md.Node node,
    TextStyle textStyle,
    GestureRecognizer? link,
  ) {
    if (node is md.Text) {
      var text = node.text;
      if (!settings.newlinesAsBreaks) text = text.replaceAll('\n', ' ');
      return [TextSpan(text: text, recognizer: link)];
    }
    if (node is! md.Element) {
      return [TextSpan(text: node.textContent, recognizer: link)];
    }
    final children = node.children ?? const <md.Node>[];
    List<InlineSpan> styled(TextStyle extra) => [
      TextSpan(
        style: extra,
        children: [
          for (final child in children)
            ..._inline(child, textStyle.merge(extra), link),
        ],
      ),
    ];
    switch (node.tag) {
      case 'strong':
        return styled(const TextStyle(fontWeight: FontWeight.w700));
      case 'em':
        return styled(const TextStyle(fontStyle: FontStyle.italic));
      case 'del':
        return styled(const TextStyle(decoration: TextDecoration.lineThrough));
      case 'code':
        return [
          TextSpan(
            text: node.textContent,
            style: style.inlineCodeStyle,
            recognizer: link,
          ),
        ];
      case 'a':
        final href = node.attributes['href'] ?? '';
        if (!isAllowedUrl(href, settings.linkSchemes)) {
          // shown as text: the model may have produced a harmful link
          return [
            for (final child in children) ..._inline(child, textStyle, link),
          ];
        }
        final recognizer = recognizers.take()
          ..onTap = () => settings.onLinkTap?.call(href);
        return [
          TextSpan(
            style: style.linkStyle,
            children: [
              for (final child in children)
                ..._inline(child, textStyle.merge(style.linkStyle), recognizer),
            ],
          ),
        ];
      case 'br':
        return const [TextSpan(text: '\n')];
      case 'img':
        return [
          WidgetSpan(
            child: _image(node.attributes['src'], node.attributes['alt']),
          ),
        ];
      case 'input':
        return [WidgetSpan(child: _checkbox(node, textStyle))];
      case inlineMathTag:
        final tex = node.textContent;
        final display = node.attributes['display'] == 'true';
        final builder = settings.mathBuilder;
        if (builder == null) {
          return [
            TextSpan(
              text: display ? '\$\$$tex\$\$' : '\$$tex\$',
              style: style.inlineCodeStyle,
            ),
          ];
        }
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _mathSemantics(tex, builder(context, tex, display)),
          ),
        ];
      case 'sup':
        return styled(TextStyle(fontSize: (textStyle.fontSize ?? 14) * 0.75));
      default:
        return [
          for (final child in children) ..._inline(child, textStyle, link),
        ];
    }
  }

  Widget _image(String? source, String? alt) {
    final uri = Uri.tryParse(source ?? '');
    if (uri == null || !isAllowedUrl(source, settings.imageSchemes)) {
      return Text(alt ?? '', style: style.textStyle);
    }
    final builder = settings.imageBuilder;
    if (builder != null) return builder(context, uri, alt);
    return Image.network(
      uri.toString(),
      semanticLabel: alt,
      errorBuilder: (context, error, stackTrace) =>
          Text(alt ?? '', style: style.textStyle),
    );
  }

  Widget _checkbox(md.Element input, TextStyle textStyle) {
    final checked = input.attributes['checked'] == 'true';
    final size = (textStyle.fontSize ?? 14) * 1.2;
    return Semantics(
      checked: checked,
      child: MarkdownIcon(
        checked ? MarkdownIconKind.checkedBox : MarkdownIconKind.box,
        size: size,
        color: textStyle.color ?? const Color(0xFF808080),
        accentColor: style.accentColor,
      ),
    );
  }

  Widget _list(md.Element list) {
    final ordered = list.tag == 'ol';
    var number = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    const bullets = ['•', '◦', '▪'];
    final bullet = bullets[_listDepth % bullets.length];
    final items = <Widget>[];
    _listDepth++;
    for (final item in list.children ?? const <md.Node>[]) {
      if (item is! md.Element || item.tag != 'li') continue;
      var children = item.children ?? const <md.Node>[];
      Widget marker;
      final first = children.isEmpty ? null : children.first;
      if (first is md.Element && first.tag == 'input') {
        marker = Align(
          alignment: AlignmentDirectional.topStart,
          child: _checkbox(first, style.textStyle),
        );
        children = children.sublist(1);
      } else {
        marker = Text(
          ordered ? '$number.' : bullet,
          style: style.textStyle,
          textAlign: TextAlign.start,
        );
      }
      number++;
      items.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: style.listIndent, child: marker),
            Expanded(child: blocks(children, parent: item)),
          ],
        ),
      );
    }
    _listDepth--;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: style.blockSpacing / 3),
          items[i],
        ],
      ],
    );
  }

  Widget _codeBlock(md.Element pre) {
    final children = pre.children ?? const <md.Node>[];
    final code = children.isNotEmpty && children.first is md.Element
        ? children.first as md.Element
        : null;
    var text = code?.textContent ?? pre.textContent;
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
    final className = code?.attributes['class'] ?? '';
    final language = className.startsWith('language-')
        ? className.substring('language-'.length)
        : null;
    final custom = settings.codeBlockBuilder?.call(
      context,
      text,
      language,
      isComplete,
    );
    if (custom != null) return custom;
    return CodeBlockView(
      code: text,
      language: language,
      style: style,
      highlight: isComplete && settings.highlightCode,
      trailing: identical(pre, cursorTarget) && settings.showCursor
          ? _cursor(style.codeBlockTextStyle)
          : null,
      fadeLength: identical(pre, cursorTarget) ? settings.fadeLength : 0,
    );
  }

  Widget _table(md.Element table) {
    final rows = <TableRow>[];
    for (final section in table.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      final header = section.tag == 'thead';
      for (final row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') continue;
        final cells = <Widget>[];
        for (final cell in row.children ?? const <md.Node>[]) {
          if (cell is! md.Element) continue;
          final textStyle = header
              ? style.textStyle.copyWith(fontWeight: FontWeight.w700)
              : style.textStyle;
          final align = switch (cell.attributes['align']) {
            'center' => TextAlign.center,
            'right' => TextAlign.end,
            _ => TextAlign.start,
          };
          final spans = <InlineSpan>[
            for (final node in cell.children ?? const <md.Node>[])
              ..._inline(node, textStyle, null),
          ];
          if (identical(cell, cursorTarget)) {
            final tail = _streamingTail(spans, textStyle);
            spans
              ..clear()
              ..addAll(tail);
          }
          cells.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text.rich(
                TextSpan(style: textStyle, children: spans),
                textAlign: align,
              ),
            ),
          );
        }
        if (cells.isEmpty) continue;
        rows.add(
          TableRow(
            decoration: header
                ? BoxDecoration(color: style.tableHeaderColor)
                : null,
            children: cells,
          ),
        );
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows.first.children.length;
    final complete = [
      for (final row in rows)
        if (row.children.length == columns) row,
    ];
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: style.dividerColor),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: complete,
        ),
      ),
    );
  }
}
