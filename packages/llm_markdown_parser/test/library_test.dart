import 'dart:io';

import 'package:llm_markdown_parser/llm_markdown_parser.dart';
import 'package:test/test.dart';

// every file the parser library reaches, through imports and exports
Set<String> _reached(String start) {
  final seen = <String>{};
  final directive = RegExp(r"^(?:import|export) '([^']+)'", multiLine: true);
  void visit(String path) {
    if (!seen.add(path)) return;
    final source = File(path).readAsStringSync();
    for (final match in directive.allMatches(source)) {
      final uri = match[1]!;
      if (uri.startsWith('package:') || uri.startsWith('dart:')) {
        seen.add(uri);
      } else {
        visit(File(path).parent.uri.resolve(uri).toFilePath());
      }
    }
  }

  visit(start);
  return seen;
}

void main() {
  test('nothing in the package imports Flutter', () {
    final reached = _reached(
      File('lib/llm_markdown_parser.dart').absolute.path,
    );
    expect(reached.where((uri) => uri.contains('package:flutter')), isEmpty);
    expect(reached, contains('package:markdown/markdown.dart'));
  });

  test('the package does not need the Flutter SDK', () {
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('flutter')));
  });

  test('it parses a streamed reply', () {
    const reply = '<think>plan</think>\n\n# Title\n\nSome **bold** text.\n';
    final split = splitThinking(reply, complete: true);
    final parser = IncrementalMarkdownParser();
    for (var i = 1; i <= split.answer.length; i++) {
      parser.update(split.answer.substring(0, i), complete: false);
    }
    parser.update(split.answer, complete: true);
    expect(split.thinking, 'plan');
    expect(parser.frozenBlocks.map((b) => b.nodes.single.textContent), [
      'Title',
      'Some bold text.',
    ]);
    expect(healIncompleteMarkdown('Some **bo'), 'Some **bo**');
    expect(markdownToPlainText(reply), contains('Some bold text.'));
  });
}
