// Streams a reply into the parser chunk by chunk, the way it arrives from a
// model, and prints what is finished after each chunk.
import 'package:llm_markdown_parser/llm_markdown_parser.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  const chunks = [
    '<think>Keep it short.</think>',
    '# Stream',
    'ing\n\nSome **bo',
    'ld** text and a [li',
    'nk](https://dart.dev).\n\n```dart\nprint(',
    "'hi');\n```\n",
  ];

  final parser = IncrementalMarkdownParser();
  var reply = '';
  for (final chunk in chunks) {
    reply += chunk;
    final split = splitThinking(reply, complete: false);
    parser.update(split.answer, complete: false);
    print(
      '${parser.frozenBlocks.length} finished, open block: '
      '${md.renderToHtml(parser.openNodes).replaceAll('\n', r'\n')}',
    );
  }

  final split = splitThinking(reply, complete: true);
  parser.update(split.answer, complete: true);
  print('\nThinking: ${split.thinking}');
  print('Plain text:\n${markdownToPlainText(reply)}');
  print(
    '\nHTML:\n${md.renderToHtml([for (final block in parser.frozenBlocks) ...block.nodes])}',
  );
}
