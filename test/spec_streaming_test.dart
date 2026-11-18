// Streams every example of the CommonMark and GitHub specs and checks it
// ends up exactly like a one-shot parse, and that finished blocks never
// change on the way. The examples come from the markdown package's own
// test files, so nothing is copied here.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/incremental_parser.dart';
import 'package:llm_markdown/src/math.dart';
import 'package:markdown/markdown.dart' as md;

Directory? _specs() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return null;
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final markdown = packages.cast<Map>().firstWhere(
    (p) => p['name'] == 'markdown',
    orElse: () => const {},
  );
  final root = markdown['rootUri'] as String?;
  if (root == null) return null;
  final dir = Directory.fromUri(
    config.absolute.uri.resolve(root.endsWith('/') ? root : '$root/'),
  );
  final test = Directory('${dir.path}test');
  return test.existsSync() ? test : null;
}

List<(String, String)> _examples() {
  final dir = _specs();
  if (dir == null) return const [];
  final examples = <(String, String)>[];
  for (final folder in ['common_mark', 'gfm']) {
    final files =
        Directory('${dir.path}/$folder')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.unit'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      String? name;
      final input = StringBuffer();
      var reading = false;
      for (final line in const LineSplitter().convert(
        file.readAsStringSync(),
      )) {
        if (line.startsWith('>>>')) {
          name = '$folder/${line.substring(3).trim()}';
          input.clear();
          reading = true;
        } else if (line == '<<<' && name != null) {
          examples.add((name, input.toString()));
          reading = false;
        } else if (reading) {
          input.writeln(line);
        }
      }
    }
  }
  return examples;
}

// a link definition, also inside a quote or list item
final RegExp _definition = RegExp(
  r'^[ >]*(?:(?:[-*+]|\d{1,9}[.)]) +)?\[[^\]]+\]:',
  multiLine: true,
);

String _html(md.Node node) =>
    node is md.Text ? node.text.trim() : md.renderToHtml([node]);

class _Broken extends md.InlineSyntax {
  _Broken() : super('boom');

  @override
  bool onMatch(md.InlineParser parser, Match match) =>
      throw StateError('broken syntax');
}

void main() {
  final examples = _examples();

  test('a link definition ending in a backslash does not crash', () {
    // markdown 7.3.1 throws a RangeError for this line on its own
    final nodes = newMarkdownDocument().parse('[foo]\n\n[foo]: /url\\\n');
    expect(md.renderToHtml(nodes), contains('<a href="/url'));
    expect(newMarkdownDocument().parse('> - [x]: \\'), isNotEmpty);
  });

  test('a parser bug shows the text instead of throwing', () {
    final nodes = newMarkdownDocument(
      MarkdownSyntax(inlineSyntaxes: [_Broken()]),
    ).parse('it goes boom');
    expect(nodes.single.textContent, 'it goes boom');
  });

  test('the spec examples are found', () {
    expect(examples.length, greaterThan(1000));
  }, skip: examples.isEmpty ? 'markdown package tests not found' : false);

  test('every spec example streams like a one-shot parse', () {
    final failures = <String>[];
    for (final (name, text) in examples) {
      final expected = newMarkdownDocument().parse(text).map(_html).toList();
      final strict = !_definition.hasMatch(text);
      final parser = IncrementalMarkdownParser();
      String? failure;
      for (var end = 1; end <= text.length && failure == null; end++) {
        try {
          parser.update(text.substring(0, end), complete: false);
        } catch (error) {
          failure =
              '$name, after ${jsonEncode(text.substring(0, end))}: $error';
          break;
        }
        if (!strict) continue;
        final frozen = [
          for (final block in parser.frozenBlocks)
            for (final node in block.nodes) _html(node),
        ];
        for (var i = 0; i < frozen.length; i++) {
          if (i >= expected.length || frozen[i] != expected[i]) {
            failure =
                '$name, after ${jsonEncode(text.substring(0, end))}: '
                'block $i is ${frozen[i]}';
            break;
          }
        }
      }
      if (failure == null) {
        parser.update(text, complete: true);
        final got = [
          for (final block in parser.frozenBlocks)
            for (final node in block.nodes) _html(node),
        ];
        if (got.join('\n') != expected.join('\n')) {
          failure = '$name (complete) ${jsonEncode(text)}: got $got';
        }
      }
      if (failure != null) failures.add(failure);
    }
    expect(failures, isEmpty, reason: failures.take(15).join('\n'));
  });

  testWidgets('every spec example renders, streamed and complete', (
    tester,
  ) async {
    for (final (name, text) in examples) {
      for (final complete in [false, true]) {
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0xFF2196F3),
            builder: (context, _) => DefaultTextStyle(
              style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
              child: SingleChildScrollView(
                child: StreamingMarkdown.text(
                  text,
                  key: ValueKey('$name $complete'),
                  isComplete: complete,
                  smoothing: const Smoothing.none(),
                ),
              ),
            ),
          ),
        );
        final error = tester.takeException();
        expect(error, isNull, reason: '$name: $error');
      }
    }
  });
}
