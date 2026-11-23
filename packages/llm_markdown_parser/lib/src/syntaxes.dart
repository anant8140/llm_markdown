import 'package:meta/meta.dart';
import 'package:markdown/markdown.dart' as md;

const String citationTag = 'cite';
const String spoilerTag = 'spoiler';
const String detailsTag = 'details';

/// Which Markdown extensions are recognized, beyond GitHub-flavored
/// Markdown.
@immutable
class MarkdownSyntax {
  /// Creates a syntax configuration; everything is on by default.
  const MarkdownSyntax({
    this.dollarMath = true,
    this.alerts = true,
    this.citations = true,
    this.emoji = true,
    this.highlightAndSpoilers = true,
    this.inlineHtml = true,
    this.details = true,
    this.autolinks = true,
    this.autolinkSchemes = const {},
    this.blockSyntaxes = const [],
    this.inlineSyntaxes = const [],
  });

  /// Whether `$...$` and `$$...$$` are math. `\(...\)` and `\[...\]` always
  /// are. Turn it off when replies talk about prices a lot.
  final bool dollarMath;

  /// GitHub alerts: `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` and
  /// `[!CAUTION]`.
  final bool alerts;

  /// `[1]`, `[2]` after a word become citation chips.
  final bool citations;

  /// `:rocket:` becomes 🚀.
  final bool emoji;

  /// `==highlight==` and `||spoiler||`.
  final bool highlightAndSpoilers;

  /// A small set of HTML tags: `<sub> <sup> <kbd> <mark> <u> <ins> <small>`,
  /// `<b> <strong> <i> <em> <s> <del> <strike> <code>` and `<br>`, around
  /// plain text. Other HTML shows as text.
  final bool inlineHtml;

  /// `<details><summary>Title</summary> ... </details>` sections.
  final bool details;

  /// Whether bare `https://` and `www.` addresses become links.
  final bool autolinks;

  /// More schemes to turn into links when written bare, e.g. `{'myapp'}`
  /// for `myapp://home`. They still have to be allowed by
  /// `StreamingMarkdown.allowedLinkSchemes` to open.
  final Set<String> autolinkSchemes;

  /// Your own block syntaxes from `package:markdown`, tried before the
  /// built-in ones. Show what they make with
  /// `StreamingMarkdown.elementBuilders`.
  ///
  /// While a reply streams, a block is finished at the first blank line
  /// outside code, math and `<details>`, so a custom block must not contain
  /// blank lines.
  final List<md.BlockSyntax> blockSyntaxes;

  /// Your own inline syntaxes from `package:markdown`, tried before the
  /// built-in ones, e.g. for `@mentions`.
  final List<md.InlineSyntax> inlineSyntaxes;

  @override
  bool operator ==(Object other) =>
      other is MarkdownSyntax &&
      other.dollarMath == dollarMath &&
      other.alerts == alerts &&
      other.citations == citations &&
      other.emoji == emoji &&
      other.highlightAndSpoilers == highlightAndSpoilers &&
      other.inlineHtml == inlineHtml &&
      other.details == details &&
      other.autolinks == autolinks &&
      other.autolinkSchemes.length == autolinkSchemes.length &&
      other.autolinkSchemes.containsAll(autolinkSchemes) &&
      _sameSyntaxes(other.blockSyntaxes, blockSyntaxes) &&
      _sameSyntaxes(other.inlineSyntaxes, inlineSyntaxes);

  @override
  int get hashCode => Object.hash(
    dollarMath,
    alerts,
    citations,
    emoji,
    highlightAndSpoilers,
    inlineHtml,
    details,
    autolinks,
    Object.hashAllUnordered(autolinkSchemes),
    Object.hashAll(blockSyntaxes.map(_syntaxKey)),
    Object.hashAll(inlineSyntaxes.map(_syntaxKey)),
  );
}

// Syntaxes made again on every build are still the same syntax, so the
// parser isn't thrown away each time.
(Type, String) _syntaxKey(Object syntax) => (
  syntax.runtimeType,
  switch (syntax) {
    final md.BlockSyntax block => block.pattern.pattern,
    final md.InlineSyntax inline => inline.pattern.pattern,
    _ => '',
  },
);

bool _sameSyntaxes(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (_syntaxKey(a[i]) != _syntaxKey(b[i])) return false;
  }
  return true;
}

class HighlightSyntax extends md.InlineSyntax {
  // not between word characters: a==b && c==d is code
  HighlightSyntax() : super(r'(?<![\w=])==(?=\S)(.+?)(?<=\S)==(?![\w=])');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mark', match[1]!));
    return true;
  }
}

class SpoilerSyntax extends md.InlineSyntax {
  SpoilerSyntax() : super(r'(?<![\w|])\|\|(?=\S)(.+?)(?<=\S)\|\|(?![\w|])');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(spoilerTag, match[1]!));
    return true;
  }
}

// [1] right after text, not a link ([text][1], [1](url), [1]: url) and not
// array indexing (a[1]). Several in a row, [1][2], are all citations.
class CitationSyntax extends md.InlineSyntax {
  CitationSyntax() : super(r'(?<![\w\[])\[(\d{1,3})\](?![(:])');

  static final RegExp _citationBefore = RegExp(
    r'(?<![\w\[\]])(?:\[\d{1,3}\])+$',
  );
  static final RegExp _citationAfter = RegExp(r'\[(\d{1,3})\]');

  // Checked here and not in onMatch: an onMatch that returns false makes
  // the inline parser try the same spot again, forever.
  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final match = pattern.matchAsPrefix(
      parser.source,
      startMatchPos ?? parser.pos,
    );
    if (match == null) return false;
    final source = parser.source;
    final references = parser.document.linkReferences;
    // a reference link such as [1]: https://... is a link, not a citation
    if (references.containsKey(match[1])) return false;
    // after "]" only when that closes a citation too: [1][2], not [text][2]
    if (match.start > 0 &&
        source[match.start - 1] == ']' &&
        !_citationBefore.hasMatch(source.substring(0, match.start))) {
      return false;
    }
    // before "[" only when that is a citation and not the name of a
    // reference: with "[2]: url" defined, [1][2] is a link
    if (source.startsWith('[', match.end)) {
      final next = _citationAfter.matchAsPrefix(source, match.end);
      if (next == null || references.containsKey(next[1])) return false;
    }
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(citationTag, match[1]!));
    return true;
  }
}

// HTML tags that mean the same as a Markdown element.
const _sameAs = {'b': 'strong', 'i': 'em', 's': 'del', 'strike': 'del'};

class SafeHtmlSyntax extends md.InlineSyntax {
  SafeHtmlSyntax()
    : super(
        r'<(sub|sup|kbd|mark|u|ins|small|b|strong|i|em|s|del|strike|code)>([^<]*)</\1>|<br\s*/?>',
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tag = match[1]?.toLowerCase();
    parser.addNode(
      tag == null
          ? md.Element.empty('br')
          : md.Element.text(_sameAs[tag] ?? tag, match[2]!),
    );
    return true;
  }
}

class SchemeAutolinkSyntax extends md.InlineSyntax {
  SchemeAutolinkSyntax(Set<String> schemes)
    : super(
        // ends before the punctuation that closes the sentence
        '(?<![\\w/])(?:${schemes.map(RegExp.escape).join('|')})://'
        '[^\\s<>()]*[^\\s<>().,;:!?\'"]',
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final url = match[0]!;
    parser.addNode(md.Element.text('a', url)..attributes['href'] = url);
    return true;
  }
}

final RegExp detailsOpener = RegExp(
  r'^ {0,3}<details(?:\s[^>]*)?>',
  caseSensitive: false,
);
final RegExp detailsCloser = RegExp(r'</details>\s*$', caseSensitive: false);
final RegExp _summary = RegExp(
  r'<summary>(.*?)</summary>',
  caseSensitive: false,
);

class DetailsBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => detailsOpener;

  @override
  bool canEndBlock(md.BlockParser parser) => true;

  @override
  md.Node parse(md.BlockParser parser) {
    final lines = <String>[];
    var depth = 0;
    var closed = false;
    while (!parser.isDone) {
      final line = parser.current.content;
      parser.advance();
      if (detailsOpener.hasMatch(line)) depth++;
      if (detailsCloser.hasMatch(line)) depth--;
      lines.add(line);
      if (depth <= 0) {
        closed = true;
        break;
      }
    }
    var body = lines.join('\n');
    var summary = 'Details';
    final match = _summary.firstMatch(body);
    if (match != null) {
      summary = match[1]!.trim();
      body = body.replaceFirst(match[0]!, '');
    }
    body = body
        .replaceFirst(detailsOpener, '')
        .replaceFirst(RegExp(r'</details>\s*$', caseSensitive: false), '');
    final children = md.BlockParser(
      body.split('\n').map(md.Line.new).toList(),
      parser.document,
    ).parseLines();
    return md.Element(detailsTag, children)
      ..attributes['summary'] = summary
      ..attributes['closed'] = '$closed';
  }
}

// GitHub alerts with the same continuation rules as a block quote. The
// markdown package's AlertBlockSyntax also swallows lines without ">" up to
// the next blank line, which GitHub doesn't do.
class AlertSyntax extends md.BlockquoteSyntax {
  const AlertSyntax();

  static final RegExp _alert = RegExp(
    r'^ {0,3}>[ \t]*\[!(note|tip|important|warning|caution)\][ \t]*$',
    caseSensitive: false,
  );

  static const _titles = {
    'note': 'Note',
    'tip': 'Tip',
    'important': 'Important',
    'warning': 'Warning',
    'caution': 'Caution',
  };

  // The block quote pattern stays: parseChildLines uses it to find the
  // following "> " lines. Only the first line has to be an alert marker.
  @override
  bool canParse(md.BlockParser parser) =>
      _alert.hasMatch(parser.current.content);

  @override
  md.Node parse(md.BlockParser parser) {
    final type = _alert.firstMatch(parser.current.content)![1]!.toLowerCase();
    final lines = parseChildLines(parser).skip(1).toList();
    final children = md.BlockParser(
      lines,
      parser.document,
    ).parseLines(parentSyntax: this);
    return md.Element('div', [
      md.Element('p', [md.Text(_titles[type]!)])
        ..attributes['class'] = 'markdown-alert-title',
      ...children,
    ])..attributes['class'] = 'markdown-alert markdown-alert-$type';
  }
}
