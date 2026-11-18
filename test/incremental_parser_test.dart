import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/src/incremental_parser.dart';
import 'package:markdown/markdown.dart' as md;

import 'support/corpus.dart';

md.Document _document() => md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  encodeHtml: false,
);

/// Renders one top-level node. Raw HTML blocks are top-level text nodes, and
/// the markdown package starts one with a newline when a blank line precedes
/// it in the same parse; that newline is not shown, so it is trimmed here.
String _html(md.Node node) =>
    node is md.Text ? node.text.trim() : md.renderToHtml([node]);

List<String> _oneShot(String text) =>
    _document().parse(text).map(_html).toList();

List<String> _frozenHtml(IncrementalMarkdownParser parser) => [
  for (final block in parser.frozenBlocks)
    for (final node in block.nodes) _html(node),
];

/// Feeds [chunks] one at a time and checks after every chunk that the frozen
/// blocks equal the start of the one-shot result for the whole [text].
void _expectStreamsLikeOneShot(String text, List<String> chunks) {
  final expected = _oneShot(text);
  final parser = IncrementalMarkdownParser();
  var received = '';
  for (final chunk in chunks) {
    received += chunk;
    parser.update(received, complete: false);
    final frozen = _frozenHtml(parser);
    expect(
      frozen.length <= expected.length &&
          _listEquals(frozen, expected.sublist(0, frozen.length)),
      isTrue,
      reason:
          'After ${received.length} characters a frozen block differs from '
          'the one-shot parse.\nfrozen: $frozen\nexpected: $expected',
    );
  }
  parser.update(received, complete: true);
  expect(_frozenHtml(parser), expected);
  expect(parser.openNodes, isEmpty);
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<String> _randomChunks(String text, Random random, int maxSize) {
  final chunks = <String>[];
  var i = 0;
  while (i < text.length) {
    final size = 1 + random.nextInt(maxSize);
    final end = min(text.length, i + size);
    chunks.add(text.substring(i, end));
    i = end;
  }
  return chunks;
}

void main() {
  group('streamed parse equals one-shot parse', () {
    for (final entry in corpus.entries) {
      final text = entry.value;

      test('${entry.key}: one character at a time', () {
        _expectStreamsLikeOneShot(text, text.split(''));
      });

      test('${entry.key}: random chunks', () {
        for (var seed = 0; seed < 40; seed++) {
          final random = Random(seed);
          _expectStreamsLikeOneShot(
            text,
            _randomChunks(text, random, 1 + seed % 24),
          );
        }
      });

      test('${entry.key}: line by line', () {
        _expectStreamsLikeOneShot(
          text,
          RegExp(
            r'[^\n]*\n|[^\n]+$',
          ).allMatches(text).map((m) => m[0]!).toList(),
        );
      });
    }
  });

  test('finished blocks are frozen while the answer streams', () {
    final text = corpus['answer with headings, lists and code']!;
    final parser = IncrementalMarkdownParser();
    final cut = text.indexOf('## 2. Use it');
    parser.update(text.substring(0, cut + 5), complete: false);
    expect(parser.frozenBlocks.length, greaterThanOrEqualTo(4));
    final firstIds = parser.frozenBlocks.map((b) => b.id).toList();

    parser.update(text, complete: false);
    expect(
      parser.frozenBlocks.take(firstIds.length).map((b) => b.id),
      firstIds,
      reason: 'blocks that were frozen are kept, not parsed again',
    );
  });

  test('a link reference defined later resolves earlier links', () {
    const text = 'See [the docs][d].\n\nMore text.\n\n[d]: https://dart.dev\n';
    final parser = IncrementalMarkdownParser();
    var received = '';
    for (final char in text.split('')) {
      received += char;
      parser.update(received, complete: false);
    }
    parser.update(received, complete: true);
    expect(_frozenHtml(parser), _oneShot(text));
    expect(_frozenHtml(parser).first, contains('href="https://dart.dev"'));
  });

  test('footnotes resolve across blocks', () {
    const text = 'See[^1] here.\n\nMore text.\n\n[^1]: The note.\n';
    final parser = IncrementalMarkdownParser();
    var received = '';
    for (final char in text.split('')) {
      received += char;
      parser.update(received, complete: false);
    }
    parser.update(received, complete: true);
    expect(_frozenHtml(parser), _oneShot(text));
    expect(_frozenHtml(parser).join(), contains('footnote-ref'));
  });

  test('text that does not extend the previous text is parsed again', () {
    final parser = IncrementalMarkdownParser()
      ..update('# One\n\nfirst', complete: false);
    parser.update('# Two\n', complete: true);
    expect(_frozenHtml(parser), _oneShot('# Two\n'));
  });
}
