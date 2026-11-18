import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/renderer.dart';

Widget _host(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: SingleChildScrollView(child: child),
  ),
);

String _shown(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((text) => text.text.toPlainText())
    .join('\n');

void main() {
  testWidgets('switching between controller, stream and text modes', (
    tester,
  ) async {
    final controller = StreamingMarkdownController(
      text: 'From controller',
      isComplete: true,
    );
    addTearDown(controller.dispose);
    final chunks = StreamController<String>();

    await tester.pumpWidget(_host(StreamingMarkdown(controller: controller)));
    expect(_shown(tester), contains('From controller'));

    await tester.pumpWidget(
      _host(
        StreamingMarkdown.stream(
          chunks.stream,
          smoothing: const Smoothing.none(),
        ),
      ),
    );
    chunks.add('From stream');
    await tester.pump();
    expect(_shown(tester), contains('From stream'));
    expect(_shown(tester), isNot(contains('From controller')));

    await tester.pumpWidget(_host(const StreamingMarkdown.text('From text')));
    expect(_shown(tester), contains('From text'));
    expect(_shown(tester), isNot(contains('From stream')));

    // The old stream is no longer listened to.
    expect(chunks.hasListener, isFalse);
    unawaited(chunks.close());
  });

  testWidgets('a stream error ends the reply and is reported', (tester) async {
    final chunks = StreamController<String>();
    await tester.pumpWidget(
      _host(
        StreamingMarkdown.stream(
          chunks.stream,
          smoothing: const Smoothing.none(),
        ),
      ),
    );
    chunks
      ..add('Partial answer')
      ..addError(StateError('connection lost'));
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(_shown(tester), contains('Partial answer'));
    expect(find.byType(StreamingCursor), findsNothing);
    unawaited(chunks.close());
  });

  testWidgets('reset while smoothing shows the new text at once', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(StreamingMarkdown(controller: controller)));
    controller.append('old ' * 200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    controller.reset('Fresh start', true);
    await tester.pump();
    expect(_shown(tester), contains('Fresh start'));
    expect(_shown(tester), isNot(contains('old')));
    await tester.pump(const Duration(seconds: 2));
    expect(_shown(tester), isNot(contains('old')));
  });

  testWidgets('removing the widget while it animates leaves nothing running', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(StreamingMarkdown(controller: controller)));
    controller.append('word ' * 300);
    await tester.pump(const Duration(milliseconds: 30));

    await tester.pumpWidget(_host(const SizedBox()));
    controller.append('more');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('empty complete text draws nothing', (tester) async {
    await tester.pumpWidget(_host(const StreamingMarkdown.text('')));
    expect(find.byType(RichText), findsNothing);
    expect(find.byType(StreamingCursor), findsNothing);
  });

  testWidgets('CRLF text looks the same as LF text', (tester) async {
    await tester.pumpWidget(
      _host(const StreamingMarkdown.text('# Title\n\nFirst\nsecond\n')),
    );
    final lf = _shown(tester);
    await tester.pumpWidget(
      _host(const StreamingMarkdown.text('# Title\r\n\r\nFirst\r\nsecond\r\n')),
    );
    expect(_shown(tester), lf);
  });

  testWidgets('new builder callbacks on each parent build keep the cache', (
    tester,
  ) async {
    MarkdownBlockView.debugBuildCounts.clear();
    Widget build(int round) => _host(
      StreamingMarkdown.text(
        '# Title\n\nFirst paragraph.\n\nSecond paragraph.\n',
        // New closures on every build, as written inline in a parent.
        imageBuilder: (context, uri, alt) => Text('image $round'),
        codeBlockBuilder: (context, code, language, complete) => null,
      ),
    );
    for (var round = 0; round < 5; round++) {
      await tester.pumpWidget(build(round));
    }
    expect(MarkdownBlockView.debugBuildCounts.values, everyElement(1));
  });

  testWidgets('a tap on a link survives text arriving mid-tap', (tester) async {
    String? tapped;
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
          onLinkTap: (url) => tapped = url,
        ),
      ),
    );
    controller.append('Read the [docs](https://dart.dev) and');
    await tester.pump();

    final range = find.textRange.ofSubstring('docs').evaluate().single;
    final box = range.renderObject
        .getBoxesForSelection(
          TextSelection(
            baseOffset: range.textRange.start,
            extentOffset: range.textRange.end,
          ),
        )
        .first;
    final gesture = await tester.startGesture(
      range.renderObject.localToGlobal(box.toRect().center),
    );
    controller.append(' then some more words');
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(tapped, 'https://dart.dev');
  });

  testWidgets('a stream that was already read gives a clear error', (
    tester,
  ) async {
    final chunks = StreamController<String>();
    await tester.pumpWidget(_host(StreamingMarkdown.stream(chunks.stream)));
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpWidget(_host(StreamingMarkdown.stream(chunks.stream)));
    final error = tester.takeException();
    expect(error, isA<FlutterError>());
    expect('$error', contains('StreamingMarkdownController'));
    unawaited(chunks.close());
  });
}
