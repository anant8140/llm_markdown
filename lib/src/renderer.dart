import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'code_block.dart';
import 'icons.dart';
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

class RenderSettings {
  StreamingMarkdownStyle? style;

  ValueChanged<String>? onLinkTap;

  MarkdownImageBuilder? imageBuilder;

  MarkdownCodeBlockBuilder? codeBlockBuilder;

  bool highlightCode = true;

  bool newlinesAsBreaks = false;
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
};

const Set<String> _blockTags = {
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
  const StreamingCursor({super.key, required this.color, this.fontSize = 14});

  final Color color;

  final double fontSize;

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 530),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.25).animate(_blink),
      child: Container(
        width: widget.fontSize * 0.5,
        height: widget.fontSize * 1.05,
        margin: const EdgeInsetsDirectional.only(start: 2),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    ),
  );
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
      case 'p':
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
        return DecoratedBox(
          decoration: style.blockquoteDecoration,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 14),
            child: blocks(element.children ?? const [], parent: element),
          ),
        );
      case 'ul' || 'ol':
        return _list(element);
      case 'pre':
        return _codeBlock(element);
      case 'hr':
        return Container(height: 1, color: style.dividerColor);
      case 'table':
        return _table(element);
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
    if (cursor) spans.add(_cursor(textStyle));
    return Text.rich(TextSpan(style: textStyle, children: spans));
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
    if (uri == null) return Text(alt ?? '');
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
      trailing: identical(pre, cursorTarget)
          ? _cursor(style.codeBlockTextStyle)
          : null,
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
            spans.add(_cursor(textStyle));
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
