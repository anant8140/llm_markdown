import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/code_block.dart';
import 'package:llm_markdown/src/icons.dart';
import 'package:llm_markdown/src/renderer.dart';
import 'package:llm_markdown/src/smoothing.dart';

import 'support/corpus.dart';

const Color _ink = Color(0xFF202124);

/// A host with no design library: only WidgetsApp and a DefaultTextStyle.
Widget _host(Widget child, {Color color = _ink}) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: TextStyle(fontSize: 14, color: color),
    child: child,
  ),
);

Widget _app(Widget child) => _host(SingleChildScrollView(child: child));

/// The plain text of everything drawn by the widget.
String _shownText(WidgetTester tester) => tester
    .widgetList<RichText>(
      find.descendant(
        of: find.byType(StreamingMarkdown),
        matching: find.byType(RichText),
      ),
    )
    .map((text) => text.text.toPlainText())
    .join('\n');

void main() {
  testWidgets('shows complete Markdown', (tester) async {
    await tester.pumpWidget(
      _app(
        const StreamingMarkdown.text(
          '# Title\n\nSome **bold** and `code`.\n\n- one\n- two\n',
        ),
      ),
    );
    final shown = _shownText(tester);
    expect(shown, contains('Title'));
    expect(shown, contains('Some bold and code.'));
    expect(shown, contains('one'));
    expect(shown, isNot(contains('**')));
    expect(find.byType(StreamingCursor), findsNothing);
  });

  testWidgets('builds each finished block once while text streams', (
    tester,
  ) async {
    MarkdownBlockView.debugBuildCounts.clear();
    final controller = StreamingMarkdownController();
    await tester.pumpWidget(
      _app(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
        ),
      ),
    );
    final text = corpus['answer with headings, lists and code']!;
    for (var i = 0; i < text.length; i += 7) {
      controller.append(text.substring(i, i + 7 > text.length ? null : i + 7));
      await tester.pump();
    }
    controller.complete();
    await tester.pump();

    final counts = MarkdownBlockView.debugBuildCounts;
    expect(counts.length, greaterThan(5));
    expect(
      counts.values.every((count) => count == 1),
      isTrue,
      reason: 'build counts by block id: $counts',
    );
  });

  testWidgets('smoothing reveals a burst gradually and then catches up', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    await tester.pumpWidget(
      _app(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.adaptive(
            charactersPerSecond: 100,
            maxLag: Duration(seconds: 1),
          ),
        ),
      ),
    );
    controller.append('a' * 400);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final early = _shownText(tester).length;
    expect(early, greaterThan(0));
    expect(early, lessThan(400));

    await tester.pump(const Duration(milliseconds: 200));
    expect(_shownText(tester).length, greaterThan(early));

    await tester.pump(const Duration(seconds: 2));
    expect(_shownText(tester), contains('a' * 400));
  });

  testWidgets('without smoothing text shows as soon as it arrives', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    await tester.pumpWidget(
      _app(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
        ),
      ),
    );
    controller.append('Hello world');
    await tester.pump();
    expect(_shownText(tester), contains('Hello world'));
  });

  testWidgets('text that is there on the first build shows at once', (
    tester,
  ) async {
    final controller = StreamingMarkdownController(text: 'a' * 300);
    await tester.pumpWidget(_app(StreamingMarkdown(controller: controller)));
    expect(_shownText(tester), contains('a' * 300));
  });

  testWidgets('unfinished syntax renders healed while streaming', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    await tester.pumpWidget(
      _app(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
        ),
      ),
    );
    controller.append('Read **the [docs](https://dart');
    await tester.pump();
    final shown = _shownText(tester);
    expect(shown, contains('Read the docs'));
    expect(shown, isNot(contains('*')));
    expect(shown, isNot(contains('](')));
  });

  testWidgets('cursor shows while streaming and goes when complete', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    await tester.pumpWidget(
      _app(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
        ),
      ),
    );
    expect(find.byType(StreamingCursor), findsOneWidget);
    controller.append('Thinking');
    await tester.pump();
    expect(find.byType(StreamingCursor), findsOneWidget);
    controller.complete();
    await tester.pump();
    expect(find.byType(StreamingCursor), findsNothing);
  });

  testWidgets('code is highlighted only once its block is closed', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    await tester.pumpWidget(
      _app(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
        ),
      ),
    );
    controller.append('```dart\nvoid main() {}\n');
    await tester.pump();
    final open = tester.widget<CodeBlockView>(find.byType(CodeBlockView));
    expect(open.highlight, isFalse);
    expect(open.language, 'dart');

    controller.append('```\n');
    await tester.pump();
    final closed = tester.widget<CodeBlockView>(find.byType(CodeBlockView));
    expect(closed.highlight, isTrue);
    expect(closed.code, 'void main() {}');
  });

  test('highlightCode colors known languages and skips unknown ones', () {
    const base = TextStyle();
    final style = StreamingMarkdownStyle.fromColors(
      textStyle: const TextStyle(color: _ink),
      accentColor: const Color(0xFF1A73E8),
    );
    final span = highlightCode('void main() {}', 'dart', base, style.codeTheme);
    expect(span, isNotNull);
    expect(span!.toPlainText(), 'void main() {}');
    expect(highlightCode('x', 'not-a-language', base, style.codeTheme), isNull);
    expect(highlightCode('x', null, base, style.codeTheme), isNull);
  });

  testWidgets('the copy button copies the code', (tester) async {
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
    await tester.pumpWidget(
      _app(const StreamingMarkdown.text('```sh\nflutter pub get\n```\n')),
    );
    MarkdownIconKind icon() =>
        tester.widget<MarkdownIcon>(find.byType(MarkdownIcon)).kind;
    expect(icon(), MarkdownIconKind.copy);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, 'flutter pub get');
    expect(icon(), MarkdownIconKind.check);
    await tester.pump(const Duration(seconds: 3));
    expect(icon(), MarkdownIconKind.copy);
  });

  testWidgets('tapping a link reports its address', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      _app(
        StreamingMarkdown.text(
          'Read the [docs](https://dart.dev) first.',
          onLinkTap: (url) => tapped = url,
        ),
      ),
    );
    await tester.tapOnText(find.textRange.ofSubstring('docs'));
    expect(tapped, 'https://dart.dev');
  });

  testWidgets('follows the end only while the user is at the bottom', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 200,
            child: ListView(
              controller: scroll,
              children: [
                StreamingMarkdown(
                  controller: controller,
                  smoothing: const Smoothing.none(),
                  autoScrollController: scroll,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      controller.append('Line $i\n\n');
      await tester.pump();
      await tester.pump();
    }
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);

    // The user drags up to read: following stops.
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pump(const Duration(seconds: 1));
    final reading = scroll.position.pixels;
    expect(reading, lessThan(scroll.position.maxScrollExtent));
    controller.append('More text\n\n');
    await tester.pump();
    await tester.pump();
    expect(scroll.position.pixels, reading);

    // Back at the bottom: following resumes.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      controller.append('Line after $i\n\n');
      await tester.pump();
      await tester.pump();
    }
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
  });

  testWidgets('keeps following in a lazy list with estimated extents', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 300,
            child: ListView.builder(
              controller: scroll,
              itemCount: 120,
              itemBuilder: (context, index) => index < 119
                  ? SizedBox(height: 20.0 + (index % 9) * 37)
                  : StreamingMarkdown(
                      controller: controller,
                      smoothing: const Smoothing.none(),
                      autoScrollController: scroll,
                    ),
            ),
          ),
        ),
      ),
    );
    // Jump to the end the way an app opens a chat at its last message.
    for (var i = 0; i < 10; i++) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
    }
    for (var i = 0; i < 40; i++) {
      controller.append('Streaming line $i with some words in it.\n\n');
      await tester.pump();
      await tester.pump();
    }
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
  });

  testWidgets('a growing text in text mode streams, a new text replaces', (
    tester,
  ) async {
    Widget build(String text, {bool complete = false}) => _app(
      StreamingMarkdown.text(
        text,
        isComplete: complete,
        smoothing: const Smoothing.none(),
      ),
    );
    await tester.pumpWidget(build('Hello'));
    await tester.pumpWidget(build('Hello **wor'));
    expect(_shownText(tester), contains('Hello wor'));
    expect(find.byType(StreamingCursor), findsOneWidget);

    await tester.pumpWidget(build('Hello **world**', complete: true));
    expect(_shownText(tester), contains('Hello world'));
    expect(find.byType(StreamingCursor), findsNothing);

    await tester.pumpWidget(build('Bye', complete: true));
    expect(_shownText(tester), contains('Bye'));
    expect(_shownText(tester), isNot(contains('Hello')));
  });

  testWidgets('stream mode completes when the stream is done', (tester) async {
    final chunks = StreamController<String>();
    await tester.pumpWidget(
      _app(
        StreamingMarkdown.stream(
          chunks.stream,
          smoothing: const Smoothing.none(),
        ),
      ),
    );
    chunks
      ..add('## Steps\n\n')
      ..add('1. First');
    await tester.pump();
    expect(_shownText(tester), contains('First'));
    expect(find.byType(StreamingCursor), findsOneWidget);

    await chunks.close();
    await tester.pump();
    expect(find.byType(StreamingCursor), findsNothing);
  });

  testWidgets('a text style change rebuilds finished blocks', (tester) async {
    const light = Color(0xFF202124);
    const dark = Color(0xFFE8EAED);
    Widget build(Color color) =>
        _host(const StreamingMarkdown.text('Some text\n'), color: color);
    // The color of the paragraph span this package builds, not the
    // DefaultTextStyle that Text wraps around it.
    Color? paragraphColor() {
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final paragraph = (rich.text as TextSpan).children!.first as TextSpan;
      return paragraph.style?.color;
    }

    await tester.pumpWidget(build(light));
    expect(paragraphColor(), light);
    await tester.pumpWidget(build(dark));
    expect(paragraphColor(), dark);
  });

  group('StreamingMarkdownController', () {
    test('append after complete throws until reset', () {
      final controller = StreamingMarkdownController()
        ..append('a')
        ..complete();
      expect(() => controller.append('b'), throwsStateError);
      final generation = controller.generation;
      controller.reset('new');
      expect(controller.generation, generation + 1);
      expect(controller.text, 'new');
      controller.append('er');
      expect(controller.text, 'newer');
    });

    test('addStream appends every chunk and completes', () async {
      final controller = StreamingMarkdownController();
      await controller.addStream(Stream.fromIterable(['a', 'b', 'c']));
      expect(controller.text, 'abc');
      expect(controller.isComplete, isTrue);
    });
  });

  test('grapheme boundaries never split a letter or an emoji', () {
    const text = 'નમસ્તે 👨‍👩‍👧';
    final boundaries = {
      for (var i = 0; i <= text.length; i++) graphemeBoundaryAtOrAfter(text, i),
    };
    var position = 0;
    final expected = {0};
    for (final character in text.characters) {
      position += character.length;
      expected.add(position);
    }
    expect(boundaries, expected);
  });
}
