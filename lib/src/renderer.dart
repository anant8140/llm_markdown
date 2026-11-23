import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'code_block.dart';
import 'code_options.dart';
import 'direction.dart';
import 'fade.dart';
import 'headings.dart';
import 'icons.dart';
import 'labels.dart';
import 'mermaid/mermaid_view.dart';
import 'package:llm_markdown_parser/llm_markdown_parser.dart';
import 'safety.dart';
import 'thinking.dart';
import 'style.dart';
import 'svg_image.dart';

/// Builds a widget for an image, given its address and alternative text.
typedef MarkdownImageBuilder =
    Widget Function(BuildContext context, Uri uri, String? alt);

/// The cells of a table as plain text, given to a [MarkdownTableBuilder].
class MarkdownTableData {
  /// The [rows] of a table; the first is the header when [hasHeader].
  const MarkdownTableData(this.rows, {this.hasHeader = true});

  /// The text of each cell, row by row, without formatting.
  final List<List<String>> rows;

  /// Whether the first row is the header.
  final bool hasHeader;

  /// The table as CSV, for copying into a spreadsheet: cells with a comma,
  /// a quote or a line break are quoted.
  ///
  /// With [guardFormulas], a cell a spreadsheet would run as a formula
  /// (starting with `=` or `@`, or with `+` or `-` before something that is
  /// not a number) gets a leading `'`, since the text comes from a model.
  String toCsv({bool guardFormulas = true}) =>
      _separated(',', guardFormulas: guardFormulas);

  /// The table as tab-separated text, which pastes into spreadsheets as
  /// cells; tabs and line breaks inside a cell become spaces.
  String toTsv({bool guardFormulas = true}) =>
      _separated('\t', guardFormulas: guardFormulas);

  static final _formula = RegExp(r'^(=|@|[+-](?![\d.]))');

  String _separated(String separator, {required bool guardFormulas}) => rows
      .map(
        (row) => row
            .map((cell) {
              var text = cell;
              if (guardFormulas && _formula.hasMatch(text)) text = "'$text";
              if (separator == '\t') {
                return text.replaceAll(RegExp(r'[\t\r\n]+'), ' ');
              }
              return text.contains(RegExp('[",\r\n]'))
                  ? '"${text.replaceAll('"', '""')}"'
                  : text;
            })
            .join(separator),
      )
      .join('\n');
}

/// Wraps or replaces a table: [table] is the built table, [data] its cells
/// as text, for example to add a "Copy as CSV" button above it.
typedef MarkdownTableBuilder =
    Widget Function(BuildContext context, Widget table, MarkdownTableData data);

/// Builds the widget for a Markdown element, such as one made by a custom
/// syntax, or returns null for the default look.
///
/// [isComplete] is false while the element is still streaming. Elements
/// inside a paragraph become inline widgets.
typedef MarkdownElementBuilder =
    Widget? Function(BuildContext context, md.Element element, bool isComplete);

/// Builds the cursor shown at the end of text that is still arriving, in
/// place of the built-in one. [textStyle] is the style of the text it
/// follows.
typedef MarkdownCursorBuilder =
    Widget Function(BuildContext context, TextStyle textStyle);

/// Called when an image is tapped, with its address and alternative text.
typedef MarkdownImageTapCallback = void Function(Uri uri, String? alt);

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

  MarkdownTableBuilder? tableBuilder;

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

  ValueChanged<int>? onCitationTap;

  CodeBlockOptions codeBlocks = const CodeBlockOptions();

  MarkdownImageTapCallback? onImageTap;

  bool zoomImages = true;

  String? searchQuery;

  bool diagrams = true;

  Map<String, MarkdownElementBuilder> elementBuilders = const {};

  MarkdownLabels labels = const MarkdownLabels();

  MarkdownCursorBuilder? cursorBuilder;

  Color? searchColor;

  // footnotes and headings, so "#fn-1" links can scroll to them
  final Map<String, GlobalKey> anchors = {};
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
  detailsTag,
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
    child:
        settings.cursorBuilder?.call(context, textStyle) ??
        StreamingCursor(
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
      // a custom element between blocks is a block, except in a tight list
      // item, whose text sits right in the item
      final customBlock =
          node is md.Element &&
          parent?.tag != 'li' &&
          settings.elementBuilders.containsKey(node.tag);
      if (_isInline(node) && !customBlock) {
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
    Widget? built;
    final builder = settings.elementBuilders[element.tag];
    if (builder != null) built = builder(context, element, isComplete);
    built ??= _defaultBlock(element);
    final padding = style.blockPadding[element.tag];
    if (built == null || padding == null) return built;
    return Padding(padding: padding, child: built);
  }

  Widget? _defaultBlock(md.Element element) {
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
        final heading = Semantics(
          header: true,
          child: _paragraph(
            element.children ?? const [],
            style.headingStyles[level - 1],
            cursor: identical(element, cursorTarget),
          ),
        );
        final id = element.attributes['id'];
        return id == null
            ? heading
            : KeyedSubtree(
                key: settings.anchors.putIfAbsent(
                  headingAnchor(id),
                  GlobalKey.new,
                ),
                child: heading,
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
      case detailsTag:
        return ThinkingSection(
          // "Details" is what the parser puts when there is no <summary>
          label: switch (element.attributes['summary']) {
            null || 'Details' => settings.labels.details,
            final summary => summary,
          },
          done: true,
          color: style.codeBlockHeaderStyle.color ?? style.accentColor,
          textStyle: style.textStyle.copyWith(fontWeight: FontWeight.w600),
          initiallyExpanded: false,
          child: blocks(element.children ?? const [], parent: element),
        );
      case 'div'
          when (element.attributes['class'] ?? '').contains('markdown-alert '):
        return _alert(element);
      case 'section' when element.attributes['class'] == 'footnotes':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 1, color: style.dividerColor),
            SizedBox(height: style.blockSpacing / 2),
            blocks(element.children ?? const [], parent: element),
          ],
        );
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

  Widget _alert(md.Element alert) {
    final type = RegExp(
      r'markdown-alert-(\w+)',
    ).firstMatch(alert.attributes['class']!)![1]!;
    final color = style.alertColors[type] ?? style.accentColor;
    final children = alert.children ?? const <md.Node>[];
    final title =
        settings.labels.alertTitles[type] ??
        (children.isEmpty ? '' : children.first.textContent);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: BorderDirectional(start: BorderSide(color: color, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: style.textStyle.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (children.length > 1) ...[
              SizedBox(height: style.blockSpacing / 2),
              blocks(children.sublist(1), parent: alert),
            ],
          ],
        ),
      ),
    );
  }

  // sub/superscript as a lifted or lowered smaller text
  InlineSpan _script(String text, TextStyle textStyle, {required bool up}) {
    final size = textStyle.fontSize ?? 14;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Transform.translate(
        offset: Offset(0, up ? -size * 0.35 : size * 0.2),
        child: Text(text, style: textStyle.copyWith(fontSize: size * 0.72)),
      ),
    );
  }

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
    if (closed) {
      // no math renderer plugged in: a readable Unicode version
      return Center(
        child: Text(
          texToUnicode(tex),
          style: style.textStyle.copyWith(
            fontStyle: FontStyle.italic,
            fontSize: (style.textStyle.fontSize ?? 14) * 1.1,
          ),
          textAlign: TextAlign.center,
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
      final query = settings.searchQuery;
      if (query != null && query.isNotEmpty) {
        return _searched(text, query, link);
      }
      return [TextSpan(text: text, recognizer: link)];
    }
    if (node is! md.Element) {
      return [TextSpan(text: node.textContent, recognizer: link)];
    }
    final builder = settings.elementBuilders[node.tag];
    final built = builder?.call(context, node, isComplete);
    if (built != null) {
      return [WidgetSpan(alignment: PlaceholderAlignment.middle, child: built)];
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
        final recognizer = recognizers.take()..onTap = () => _openLink(href);
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
              text: texToUnicode(tex),
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ];
        }
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _mathSemantics(tex, builder(context, tex, display)),
          ),
        ];
      case 'sub' || 'sup' when children.every((c) => c is md.Text):
        return [_script(node.textContent, textStyle, up: node.tag == 'sup')];
      case 'mark':
        return styled(
          TextStyle(
            backgroundColor:
                style.highlightColor ??
                style.accentColor.withValues(alpha: 0.22),
          ),
        );
      case 'u' || 'ins':
        return styled(const TextStyle(decoration: TextDecoration.underline));
      case 'small':
        return styled(TextStyle(fontSize: (textStyle.fontSize ?? 14) * 0.85));
      case 'kbd':
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration:
                  style.kbdDecoration ??
                  BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: style.dividerColor),
                    color: style.tableHeaderColor,
                  ),
              child: Text(
                node.textContent,
                style: style.inlineCodeStyle.copyWith(backgroundColor: null),
              ),
            ),
          ),
        ];
      case spoilerTag:
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _Spoiler(
              text: node.textContent,
              style: textStyle,
              cover:
                  style.spoilerColor ??
                  (style.textStyle.color ?? const Color(0xFF808080)).withValues(
                    alpha: 0.85,
                  ),
              hint: settings.labels.spoilerHint,
            ),
          ),
        ];
      case citationTag:
        final number = int.parse(node.textContent);
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Semantics(
              button: true,
              label: settings.labels.citation?.call(number) ?? 'Source $number',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => settings.onCitationTap?.call(number),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration:
                      style.citationDecoration ??
                      BoxDecoration(
                        color: style.accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                  child: Text(
                    '$number',
                    style: textStyle
                        .copyWith(
                          fontSize: (textStyle.fontSize ?? 14) * 0.75,
                          color: style.accentColor,
                          fontWeight: FontWeight.w600,
                        )
                        .merge(style.citationTextStyle),
                  ),
                ),
              ),
            ),
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

  // marks every match of the search query
  List<InlineSpan> _searched(
    String text,
    String query,
    GestureRecognizer? link,
  ) {
    final spans = <InlineSpan>[];
    final found = TextStyle(
      backgroundColor:
          settings.searchColor ?? style.accentColor.withValues(alpha: 0.3),
    );
    var at = 0;
    for (final match in RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).allMatches(text)) {
      if (match.start == match.end) continue;
      if (match.start > at) {
        spans.add(
          TextSpan(text: text.substring(at, match.start), recognizer: link),
        );
      }
      spans.add(TextSpan(text: match[0], style: found, recognizer: link));
      at = match.end;
    }
    if (at < text.length || spans.isEmpty) {
      spans.add(TextSpan(text: text.substring(at), recognizer: link));
    }
    return spans;
  }

  // "#fn-1" scrolls to the footnote; anything else goes to onLinkTap
  void _openLink(String href) {
    final id = href.startsWith('#') ? href.substring(1) : null;
    final anchor = id == null
        ? null
        : (settings.anchors[id] ?? settings.anchors[headingAnchor(id)])
              ?.currentContext;
    if (anchor != null && anchor.mounted) {
      unawaited(
        Scrollable.ensureVisible(
          anchor,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
      return;
    }
    settings.onLinkTap?.call(href);
  }

  Widget _image(String? source, String? alt) {
    final uri = Uri.tryParse(source ?? '');
    if (uri == null || !isAllowedUrl(source, settings.imageSchemes)) {
      return Text(alt ?? '', style: style.textStyle);
    }
    Widget build(BuildContext context) {
      final builder = settings.imageBuilder;
      if (builder != null) return builder(context, uri, alt);
      Widget failed(BuildContext context, Object error, StackTrace? stack) =>
          Text(alt ?? '', style: style.textStyle);
      // data: images only get here when the app allowed that scheme
      final data = uri.scheme == 'data' ? uri.data : null;
      final svg = data != null
          ? data.mimeType == 'image/svg+xml'
          : uri.path.toLowerCase().endsWith('.svg');
      if (svg) {
        return SvgImage(
          uri: data == null ? uri : null,
          bytes: data?.contentAsBytes(),
          alt: alt,
          fallback: (context) => Text(alt ?? '', style: style.textStyle),
        );
      }
      if (data != null) {
        return Image.memory(
          data.contentAsBytes(),
          semanticLabel: alt,
          errorBuilder: failed,
        );
      }
      return Image.network(
        uri.toString(),
        semanticLabel: alt,
        errorBuilder: (context, error, stackTrace) =>
            Text(alt ?? '', style: style.textStyle),
      );
    }

    final navigator = Navigator.maybeOf(context);
    final zoom = settings.zoomImages && navigator != null;
    if (settings.onImageTap == null && !zoom) return build(context);
    // read when tapped: the callback may be a new closure on every build
    void tap() {
      final onTap = settings.onImageTap;
      if (onTap != null) {
        onTap(uri, alt);
        return;
      }
      if (navigator == null) return;
      unawaited(
        navigator.push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierDismissible: true,
            barrierColor: style.imageBarrierColor,
            barrierLabel: settings.labels.closeImage,
            pageBuilder: (context, _, _) => ImageViewer(
              label: settings.labels.closeImage,
              child: build(context),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      onTapHint: 'zoom',
      child: GestureDetector(
        // the whole picture takes the tap: a drawn SVG, unlike a photo,
        // doesn't take taps itself
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: build(context),
      ),
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
    final bullets = style.bullets.isEmpty ? const ['•'] : style.bullets;
    final bullet = bullets[_listDepth % bullets.length];
    final itemBuilder = settings.elementBuilders['li'];
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
      // a builder for "li" draws the whole item, marker included
      final row =
          itemBuilder?.call(context, item, isComplete) ??
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: style.listIndent, child: marker),
              Expanded(child: blocks(children, parent: item)),
            ],
          );
      final id = item.attributes['id'];
      items.add(
        id == null
            ? row
            : KeyedSubtree(
                key: settings.anchors.putIfAbsent(id, GlobalKey.new),
                child: row,
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
    // a finished mermaid block becomes a diagram; while it streams, and for
    // kinds that aren't drawn, it stays code
    if (settings.diagrams &&
        isComplete &&
        language == 'mermaid' &&
        MermaidDiagram.supports(text)) {
      return DiagramBlock(
        source: text,
        style: style,
        labels: settings.labels,
        code: CodeBlockView(
          code: text,
          language: language,
          style: style,
          highlight: false,
          options: settings.codeBlocks,
          labels: settings.labels,
        ),
      );
    }
    return CodeBlockView(
      code: text,
      language: language,
      style: style,
      highlight: isComplete && settings.highlightCode,
      trailing: identical(pre, cursorTarget) && settings.showCursor
          ? _cursor(style.codeBlockTextStyle)
          : null,
      fadeLength: identical(pre, cursorTarget) ? settings.fadeLength : 0,
      options: settings.codeBlocks,
      streaming: !isComplete,
      labels: settings.labels,
    );
  }

  Widget _table(md.Element table) {
    final rows = <TableRow>[];
    final texts = <List<String>>[];
    var hasHeader = false;
    for (final section in table.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      final header = section.tag == 'thead';
      for (final row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') continue;
        final cells = <Widget>[];
        final cellTexts = <String>[];
        for (final cell in row.children ?? const <md.Node>[]) {
          if (cell is! md.Element) continue;
          cellTexts.add(cell.textContent.trim());
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
              padding: style.tableCellPadding,
              child: Text.rich(
                TextSpan(style: textStyle, children: spans),
                textAlign: align,
              ),
            ),
          );
        }
        if (cells.isEmpty) continue;
        if (header && rows.isEmpty) hasHeader = true;
        texts.add(cellTexts);
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
    final built = Align(
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
    final builder = settings.tableBuilder;
    if (builder == null) return built;
    return builder(
      context,
      built,
      MarkdownTableData([
        for (final row in texts)
          if (row.length == columns) row,
      ], hasHeader: hasHeader),
    );
  }
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({
    required this.text,
    required this.style,
    required this.cover,
    required this.hint,
  });

  final String text;
  final TextStyle style;
  final Color cover;
  final String hint;

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: !_shown,
    label: _shown ? null : widget.hint,
    child: GestureDetector(
      onTap: () => setState(() => _shown = !_shown),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: _shown ? null : widget.cover,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          widget.text,
          style: widget.style.copyWith(
            color: _shown ? null : const Color(0x00000000),
          ),
        ),
      ),
    ),
  );
}

/// A full screen image that can be pinched and dragged; a tap closes it.
class ImageViewer extends StatelessWidget {
  const ImageViewer({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: InteractiveViewer(
        maxScale: 5,
        child: SizedBox.expand(child: Center(child: child)),
      ),
    ),
  );
}

/// A drawn diagram with a switch to its source.
class DiagramBlock extends StatefulWidget {
  const DiagramBlock({
    super.key,
    required this.source,
    required this.style,
    required this.labels,
    required this.code,
  });

  final String source;
  final StreamingMarkdownStyle style;
  final MarkdownLabels labels;
  final Widget code;

  @override
  State<DiagramBlock> createState() => _DiagramBlockState();
}

class _DiagramBlockState extends State<DiagramBlock> {
  bool _showCode = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final toggle = Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showCode = !_showCode),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            _showCode ? widget.labels.showDiagram : widget.labels.showCode,
            style: style.codeBlockHeaderStyle,
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showCode)
          widget.code
        else
          DecoratedBox(
            decoration:
                style.diagramStyle.decoration ?? style.codeBlockDecoration,
            child: Padding(
              padding: style.diagramStyle.padding,
              child: Directionality(
                // boxes and arrows keep their sides; labels find their own
                textDirection: TextDirection.ltr,
                child: MermaidDiagram(widget.source, style: style),
              ),
            ),
          ),
        Align(alignment: AlignmentDirectional.centerEnd, child: toggle),
      ],
    );
  }
}
