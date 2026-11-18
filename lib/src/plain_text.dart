import 'package:markdown/markdown.dart' as md;

import 'math.dart';
import 'thinking.dart';

/// Returns [markdown] as plain text, for example to copy a reply into an app
/// that doesn't understand Markdown.
///
/// Formatting marks are dropped, list items keep a "- " or "1. " prefix,
/// table cells are joined with " | ", code keeps its lines, and a leading
/// `<think>...</think>` section is left out.
String markdownToPlainText(String markdown) {
  final answer = splitThinking(markdown, complete: true).answer;
  final out = StringBuffer();
  _blocks(newMarkdownDocument().parse(answer), out, '');
  return out.toString().trim();
}

void _blocks(List<md.Node> nodes, StringBuffer out, String indent) {
  for (final node in nodes) {
    if (node is! md.Element) {
      final text = node.textContent.trim();
      if (text.isNotEmpty) out.writeln('$indent$text');
      continue;
    }
    switch (node.tag) {
      case 'ul' || 'ol':
        var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        for (final item in node.children ?? const <md.Node>[]) {
          if (item is! md.Element) continue;
          final marker = node.tag == 'ol' ? '${number++}. ' : '- ';
          final inner = StringBuffer();
          _blocks(_inlineAsParagraph(item.children ?? const []), inner, '');
          final lines = inner.toString().trimRight().split('\n');
          out.writeln('$indent$marker${lines.first}');
          for (final line in lines.skip(1)) {
            if (line.isNotEmpty) out.writeln('$indent   $line');
          }
        }
        out.writeln();
      case 'pre':
        out
          ..writeln(node.textContent.trimRight())
          ..writeln();
      case 'table':
        for (final row in _rows(node)) {
          out.writeln('$indent${row.join(' | ')}');
        }
        out.writeln();
      case 'blockquote':
        final inner = StringBuffer();
        _blocks(node.children ?? const [], inner, '');
        for (final line in inner.toString().trimRight().split('\n')) {
          out.writeln('$indent> $line'.trimRight());
        }
        out.writeln();
      case 'hr':
        out.writeln();
      case blockMathTag:
        out
          ..writeln('$indent${node.textContent}')
          ..writeln();
      case 'p' || 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        out
          ..writeln('$indent${_inline(node.children ?? const [])}')
          ..writeln();
      default:
        _blocks(node.children ?? const [], out, indent);
    }
  }
}

// Tight list items hold inline nodes directly.
List<md.Node> _inlineAsParagraph(List<md.Node> nodes) {
  final out = <md.Node>[];
  final inline = <md.Node>[];
  void flush() {
    if (inline.isEmpty) return;
    out.add(md.Element('p', List.of(inline)));
    inline.clear();
  }

  for (final node in nodes) {
    final isBlock =
        node is md.Element &&
        const {
          'p',
          'ul',
          'ol',
          'pre',
          'blockquote',
          'table',
          'hr',
          blockMathTag,
        }.contains(node.tag);
    if (isBlock) {
      flush();
      out.add(node);
    } else {
      inline.add(node);
    }
  }
  flush();
  return out;
}

String _inline(List<md.Node> nodes) {
  final out = StringBuffer();
  for (final node in nodes) {
    if (node is md.Element) {
      switch (node.tag) {
        case 'br':
          out.write('\n');
        case 'input':
          out.write(node.attributes['checked'] == 'true' ? '[x] ' : '[ ] ');
        case 'img':
          out.write(node.attributes['alt'] ?? '');
        default:
          out.write(_inline(node.children ?? const []));
      }
    } else {
      out.write(node.textContent.replaceAll('\n', ' '));
    }
  }
  return out.toString().trim();
}

List<List<String>> _rows(md.Element table) => [
  for (final section in table.children ?? const <md.Node>[])
    if (section is md.Element)
      for (final row in section.children ?? const <md.Node>[])
        if (row is md.Element)
          [
            for (final cell in row.children ?? const <md.Node>[])
              if (cell is md.Element) _inline(cell.children ?? const []),
          ],
];
