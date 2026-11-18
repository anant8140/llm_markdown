import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

void main() {
  const cases = <String, String>{
    // Fenced code.
    '```dart\nvoid ma': '```dart\nvoid ma\n```',
    '```pyth': '```\n```',
    '```dart\ncode\n``': '```dart\ncode\n```',
    '  ~~~\nindented': '  ~~~\nindented\n  ~~~',
    // Emphasis and strikethrough.
    '**bold': '**bold**',
    '**bold ': '**bold** ',
    'say **': 'say ',
    '*it': '*it*',
    '***both': '***both***',
    '**bold *it': '**bold *it***',
    '**bold*': '**bold**',
    'an _it': 'an _it_',
    'snake_case': 'snake_case',
    '~~old': '~~old~~',
    '2 * 3 = 6': '2 * 3 = 6',
    // Code spans.
    'use `code': 'use `code`',
    'use `': 'use ',
    '`a` and **b': '`a` and **b**',
    '`**not bold': '`**not bold`',
    r'\*not emphasis': r'\*not emphasis',
    // Links and images.
    '[docs](https://exa': 'docs',
    'see [docs](https://exa': 'see docs',
    'a ![img](https://x': 'a ',
    'see [do': 'see do',
    'see [docs](https://dart.dev)': 'see [docs](https://dart.dev)',
    // Tables.
    '| a | b |': '',
    'Here:\n| a | b |': 'Here:\n',
    '| a | b |\n|--': '',
    '| a | b |\n| --- | --- |\n| 1 | 2': '| a | b |\n| --- | --- |\n',
    '| a | b |\n| --- | --- |\n| 1 | 2 |\n':
        '| a | b |\n| --- | --- |\n| 1 | 2 |\n',
    // Lines that are only the start of a block.
    '- item\n-': '- item\n',
    '## ': '',
    'Steps:\n1.': 'Steps:\n',
    '> ': '',
    // CRLF text heals like LF text.
    '| a | b |\r\n|---|---|\r\n| 1 | 2 |\r\n| 3 | 4':
        '| a | b |\n|---|---|\n| 1 | 2 |\n',
    'Steps:\r\n#\r': 'Steps:\n',
    'foo `\r': 'foo ',
    // Ordinary text that only looks like the start of something.
    'Born in\n1990': 'Born in\n1990',
    'Steps:\n12': 'Steps:\n',
    '2*3': '2*3',
    'x * y': 'x * y',
    // Math that is still arriving is left as it is.
    '\$\$\nx^*': '\$\$\nx^*',
    '\$\$\na_1 \\\\\n-': '\$\$\na_1 \\\\\n-',
    // Complete Markdown stays as it is.
    '# Title\n\nSome **bold** text.\n': '# Title\n\nSome **bold** text.\n',
    'x\n\n': 'x\n\n',
    '': '',
  };

  for (final entry in cases.entries) {
    test('heals ${entry.key.replaceAll('\n', r'\n')}', () {
      expect(healIncompleteMarkdown(entry.key), entry.value);
    });
  }
}
