import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/src/incremental_parser.dart';
import 'package:llm_markdown/src/math.dart';
import 'package:markdown/markdown.dart' as md;

// Builds random documents out of pieces that show up in model output, plus
// some awkward ones, and checks that streaming never freezes a block that
// differs from a one-shot parse of the full text.

const _pieces = [
  'Plain paragraph text.\n',
  'Text with **bold**, *italic*, `code` and ~~strike~~.\n',
  'A line that continues\nonto a second line.\n',
  '\n',
  '\n\n',
  '# Heading\n',
  '## Heading two\n',
  '#hashtag text\n',
  'Setext title\n===\n',
  '- item\n',
  '- item\n  - nested\n',
  '* star item\n',
  '1. first\n',
  '2) second\n',
  '10. tenth\n',
  '   indented continuation\n',
  '    four-space code\n',
  '\tTabbed line\n',
  '- [ ] task\n',
  '- [x] done\n',
  '```\ncode\n```\n',
  '```dart\nvoid main() {}\n\nprint(1);\n```\n',
  '~~~\ntilde fence\n~~~\n',
  '````\n```\ninner\n```\n````\n',
  '```\n',
  '  ```js\n  indented fence\n  ```\n',
  '> quote\n',
  '> - quoted list\n',
  '>\n',
  '| a | b |\n| --- | --- |\n| 1 | 2 |\n',
  '| x |\n',
  '---\n',
  '* * *\n',
  '<div>\nhtml\n</div>\n',
  '<!-- comment\n\nmore -->\n',
  'Line with trailing spaces  \n',
  'CRLF line\r\n',
  '\u00a0\n',
  'Inline \$x^2\$ and \\(a+b\\) math, costs \$5 and \$10.\n',
  '\$\$\nE = mc^2\n\$\$\n',
  '\$\$\n\\frac{a}{b}\n\n\$\$\n',
  '\\[\nx_1\n\\]\n',
  'Display \$\$\\sum_i i\$\$ inline.\n',
  '\$\$\n',
  'emoji 🚀 and ગુજરાતી\n',
  '[link](https://dart.dev) and https://flutter.dev\n',
  '![img](https://example.com/a.png)\n',
];

md.Document _document() => newMarkdownDocument();

String _html(md.Node node) =>
    node is md.Text ? node.text.trim() : md.renderToHtml([node]);

void main() {
  test('random documents stream like a one-shot parse', () {
    final failures = <String>[];
    for (var seed = 0; seed < 600 && failures.length < 3; seed++) {
      final random = Random(seed);
      final text = [
        for (var i = 0; i < 4 + random.nextInt(14); i++)
          _pieces[random.nextInt(_pieces.length)],
      ].join();
      final expected = _document().parse(text).map(_html).toList();

      final parser = IncrementalMarkdownParser();
      var position = 0;
      var failed = false;
      while (position < text.length && !failed) {
        position = min(text.length, position + 1 + random.nextInt(9));
        parser.update(text.substring(0, position), complete: false);
        final frozen = [
          for (final block in parser.frozenBlocks)
            for (final node in block.nodes) _html(node),
        ];
        for (var i = 0; i < frozen.length; i++) {
          if (i >= expected.length || frozen[i] != expected[i]) {
            failures.add(
              'seed $seed, ${text.substring(0, position).length} chars:\n'
              '${text.substring(0, position)}\n--- frozen block $i: '
              '${frozen[i]}\n--- expected: '
              '${i < expected.length ? expected[i] : '(none)'}',
            );
            failed = true;
            break;
          }
        }
      }
      if (failed) continue;
      parser.update(text, complete: true);
      final complete = [
        for (final block in parser.frozenBlocks)
          for (final node in block.nodes) _html(node),
      ];
      if (complete.join('\n') != expected.join('\n')) {
        failures.add('seed $seed (complete):\n$text\n--- got: $complete');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n\n'));
  });
}
