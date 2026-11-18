import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/code_block.dart';
import 'package:llm_markdown/src/code_options.dart';
import 'package:llm_markdown/src/renderer.dart';

Widget _host(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: SingleChildScrollView(child: child),
  ),
);

String _code(int lines) =>
    '```dart\n${[for (var i = 1; i <= lines; i++) 'line $i;'].join('\n')}\n```\n';

Finder _inCode(Finder finder) =>
    find.descendant(of: find.byType(CodeBlockView), matching: finder);

String _codeText(WidgetTester tester) => tester
    .widgetList<RichText>(_inCode(find.byType(RichText)))
    .map((r) => r.text.toPlainText())
    .join('\n');

void main() {
  test('splitSpanLines keeps styles per line', () {
    const red = TextStyle(color: Color(0xFFFF0000));
    final lines = splitSpanLines(
      const TextSpan(
        children: [
          TextSpan(text: 'a\nb', style: red),
          TextSpan(text: 'c\n'),
        ],
      ),
      const TextStyle(),
    );
    expect(lines.length, 3);
    expect((lines[1].first as TextSpan).style?.color, red.color);
    expect(lines[1].map((s) => (s as TextSpan).text).join(), 'bc');
    expect(lines[2], isEmpty);
  });

  testWidgets('line numbers, with and without wrapping', (tester) async {
    await tester.pumpWidget(
      _host(
        StreamingMarkdown.text(
          _code(3),
          codeBlocks: const CodeBlockOptions(lineNumbers: true),
        ),
      ),
    );
    expect(find.text('1\n2\n3'), findsOneWidget);
    expect(_inCode(find.byType(SingleChildScrollView)), findsOneWidget);

    await tester.pumpWidget(
      _host(
        StreamingMarkdown.text(
          _code(3),
          codeBlocks: const CodeBlockOptions(
            lineNumbers: true,
            wrapLines: true,
          ),
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);
    expect(_inCode(find.byType(SingleChildScrollView)), findsNothing);
  });

  testWidgets('wrapLines drops the sideways scroll', (tester) async {
    await tester.pumpWidget(
      _host(
        StreamingMarkdown.text(
          _code(2),
          codeBlocks: const CodeBlockOptions(wrapLines: true),
        ),
      ),
    );
    expect(_inCode(find.byType(SingleChildScrollView)), findsNothing);
    expect(_codeText(tester), contains('line 2;'));
  });

  testWidgets('long blocks collapse until "Show all"', (tester) async {
    await tester.pumpWidget(
      _host(
        StreamingMarkdown.text(
          _code(40),
          codeBlocks: const CodeBlockOptions(collapseAfterLines: 10),
        ),
      ),
    );
    expect(_codeText(tester), contains('line 10;'));
    expect(_codeText(tester), isNot(contains('line 11;')));
    await tester.tap(find.text('Show all 40 lines'));
    await tester.pump();
    expect(_codeText(tester), contains('line 40;'));
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('a block that is still streaming does not collapse', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
          codeBlocks: const CodeBlockOptions(collapseAfterLines: 3),
        ),
      ),
    );
    controller.append(_code(8).replaceFirst('```\n', '', 1).substring(0, 60));
    await tester.pump();
    expect(find.textContaining('Show all'), findsNothing);
  });

  testWidgets('custom copy button and extra actions', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    String? ran;
    await tester.pumpWidget(
      _host(
        StreamingMarkdown.text(
          _code(1),
          codeBlocks: CodeBlockOptions(
            copyButtonBuilder: (context, copy, done) => GestureDetector(
              onTap: copy,
              child: Text(done ? 'COPIED' : 'COPY'),
            ),
            actionsBuilder: (context, code, language) => [
              GestureDetector(
                onTap: () => ran = '$language:$code',
                child: const Text('RUN'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('COPY'));
    await tester.pump();
    expect(copied, 'line 1;');
    expect(find.text('COPIED'), findsOneWidget);
    await tester.tap(find.text('RUN'));
    expect(ran, 'dart:line 1;');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('highlightWhileStreaming colors the finished lines', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
          codeBlocks: const CodeBlockOptions(highlightWhileStreaming: true),
        ),
      ),
    );
    controller.append('```dart\nfinal a = 1;\nfinal b');
    await tester.pump();
    // the background highlighter runs on a real isolate
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();
    final view = tester.widget<CodeBlockView>(find.byType(CodeBlockView));
    expect(view.highlight, isFalse);
    var colored = 0;
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == 'final' && span.style?.color != null) colored++;
        span.children?.forEach(walk);
      }
    }

    for (final rich in tester.widgetList<RichText>(
      _inCode(find.byType(RichText)),
    )) {
      walk(rich.text);
    }
    expect(colored, greaterThanOrEqualTo(1));
    expect(_codeText(tester), contains('final b'));
  });

  test('code themes and a custom monospace font', () {
    final style = StreamingMarkdownStyle.fromColors(
      textStyle: const TextStyle(color: Color(0xFF202124)),
      accentColor: const Color(0xFF1A73E8),
      monospace: const TextStyle(fontFamily: 'JetBrains Mono'),
    ).copyWith(codeTheme: CodeThemes.github);
    expect(style.codeBlockTextStyle.fontFamily, 'JetBrains Mono');
    expect(style.inlineCodeStyle.fontFamily, 'JetBrains Mono');
    expect(identical(style.codeTheme, CodeThemes.github), isTrue);
    expect(
      highlightCode(
        'void f() {}',
        'dart',
        const TextStyle(),
        CodeThemes.vs2015,
      ),
      isNotNull,
    );
  });

  testWidgets('new builder closures keep finished blocks cached', (
    tester,
  ) async {
    MarkdownBlockView.debugBuildCounts.clear();
    for (var round = 0; round < 3; round++) {
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.text(
            '${_code(1)}\nText after.\n',
            codeBlocks: CodeBlockOptions(
              actionsBuilder: (context, code, language) => const [],
            ),
          ),
        ),
      );
    }
    expect(MarkdownBlockView.debugBuildCounts.values, everyElement(1));
  });
}
