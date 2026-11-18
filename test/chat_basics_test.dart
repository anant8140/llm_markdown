import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/renderer.dart';
import 'package:llm_markdown/src/safety.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
      child: SingleChildScrollView(child: child),
    ),
  ),
);

String _shown(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((text) => text.text.toPlainText())
    .join('\n');

void _mockClipboard(WidgetTester tester, void Function(String?) onCopy) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        onCopy((call.arguments as Map)['text'] as String?);
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
}

void main() {
  group('link and image safety', () {
    test('only listed schemes pass', () {
      const cases = {
        'https://dart.dev': true,
        'HTTP://dart.dev': true,
        'mailto:a@b.c': true,
        '/relative/path': true,
        '#anchor': true,
        'javascript:alert(1)': false,
        'JavaScript:alert(1)': false,
        'java\tscript:alert(1)': false,
        ' javascript:alert(1)': false,
        'java​script:alert(1)': false,
        'data:text/html,hi': false,
        'file:///etc/passwd': false,
        'vbscript:x': false,
      };
      for (final entry in cases.entries) {
        expect(
          isAllowedUrl(entry.key, defaultLinkSchemes),
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        isAllowedUrl('data:image/png;base64,AA', defaultImageSchemes),
        isFalse,
      );
      expect(isAllowedUrl('myapp://open', {'myapp'}), isTrue);
    });

    testWidgets('a javascript: link is plain text and does nothing', (
      tester,
    ) async {
      String? tapped;
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.text(
            'Click [here](javascript:alert(1)) or [docs](https://dart.dev).',
            onLinkTap: (url) => tapped = url,
          ),
        ),
      );
      await tester.tapOnText(find.textRange.ofSubstring('here'));
      expect(tapped, isNull);
      await tester.tapOnText(find.textRange.ofSubstring('docs'));
      expect(tapped, 'https://dart.dev');
    });

    testWidgets('a data: image shows its alt text', (tester) async {
      var built = false;
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.text(
            '![a red dot](data:image/png;base64,iVBORw0KGgo=)',
            imageBuilder: (context, uri, alt) {
              built = true;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(built, isFalse);
      expect(_shown(tester), contains('a red dot'));
    });

    testWidgets('custom schemes can be allowed', (tester) async {
      String? tapped;
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.text(
            'Open [the app](myapp://home).',
            allowedLinkSchemes: const {'myapp'},
            onLinkTap: (url) => tapped = url,
          ),
        ),
      );
      await tester.tapOnText(find.textRange.ofSubstring('the app'));
      expect(tapped, 'myapp://home');
    });
  });

  group('copying the reply', () {
    test('markdownToPlainText drops marks and keeps structure', () {
      const markdown =
          '<think>plan</think>\n'
          '# Title\n\n'
          'Some **bold** and [a link](https://x.y).\n\n'
          '- one\n- two\n\n'
          '1. first\n2. second\n\n'
          '```dart\nvoid main() {}\n```\n\n'
          '| a | b |\n| - | - |\n| 1 | 2 |\n\n'
          '> quoted\n\n'
          '- [x] done\n';
      expect(
        markdownToPlainText(markdown),
        'Title\n\n'
        'Some bold and a link.\n\n'
        '- one\n- two\n\n'
        '1. first\n2. second\n\n'
        'void main() {}\n\n'
        'a | b\n1 | 2\n\n'
        '> quoted\n\n'
        '- [x] done',
      );
    });

    testWidgets('CopyReplyButton copies Markdown or plain text', (
      tester,
    ) async {
      String? copied;
      _mockClipboard(tester, (text) => copied = text);
      final controller = StreamingMarkdownController(
        text: 'It is **42**.',
        isComplete: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              CopyReplyButton(controller: controller, label: 'md'),
              CopyReplyButton(
                controller: controller,
                plainText: true,
                label: 'plain',
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('md'));
      await tester.pump();
      expect(copied, 'It is **42**.');
      await tester.tap(find.text('plain'));
      await tester.pump();
      expect(copied, 'It is 42.');
      expect(controller.plainText, 'It is 42.');
      await tester.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('tapToSkip shows the rest at once', (tester) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StreamingMarkdown(
          controller: controller,
          tapToSkip: true,
          smoothing: const Smoothing.adaptive(
            charactersPerSecond: 20,
            maxLag: Duration(seconds: 30),
          ),
        ),
      ),
    );
    controller.append('word ' * 100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_shown(tester).length, lessThan(100));

    await tester.tap(find.byType(StreamingMarkdown));
    await tester.pump();
    expect(_shown(tester), contains('word ' * 99));
  });

  testWidgets('placeholder shows until the first text', (tester) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
          placeholder: const MarkdownShimmer(),
        ),
      ),
    );
    expect(find.byType(MarkdownShimmer), findsOneWidget);
    expect(find.byType(StreamingCursor), findsNothing);

    controller.append('Hi');
    await tester.pump();
    expect(find.byType(MarkdownShimmer), findsNothing);
    expect(_shown(tester), contains('Hi'));
  });

  group('errors', () {
    testWidgets('a stream error keeps the text and shows errorBuilder', (
      tester,
    ) async {
      final chunks = StreamController<String>();
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.stream(
            chunks.stream,
            smoothing: const Smoothing.none(),
            errorBuilder: (context, error) => Text('Failed: $error'),
          ),
        ),
      );
      chunks
        ..add('Half an answer')
        ..addError('timeout');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_shown(tester), contains('Half an answer'));
      expect(_shown(tester), contains('Failed: timeout'));
      expect(find.byType(StreamingCursor), findsNothing);
      unawaited(chunks.close());
    });

    testWidgets('completeWithError works with a controller', (tester) async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
            errorBuilder: (context, error) => const Text('Retry'),
          ),
        ),
      );
      controller
        ..append('Some text')
        ..completeWithError(StateError('lost'));
      await tester.pump();
      expect(controller.error, isA<StateError>());
      expect(find.text('Retry'), findsOneWidget);

      controller.reset();
      await tester.pump();
      expect(controller.error, isNull);
      expect(find.text('Retry'), findsNothing);
    });

    test('addStream ends with the error and rethrows it', () async {
      final controller = StreamingMarkdownController();
      final failing = Stream<String>.multi((sink) {
        sink
          ..add('a')
          ..addError('boom')
          ..close();
      });
      await expectLater(controller.addStream(failing), throwsA('boom'));
      expect(controller.isComplete, isTrue);
      expect(controller.error, 'boom');
      expect(controller.text, 'a');
    });
  });

  testWidgets('reduce motion: no reveal, no fade, nothing animating', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.adaptive(charactersPerSecond: 5),
        ),
        reduceMotion: true,
      ),
    );
    controller.append('All of this shows at once');
    await tester.pump();
    expect(_shown(tester), contains('All of this shows at once'));
    // A blinking cursor or a reveal would keep scheduling frames.
    await tester.pumpAndSettle();

    Color? faded;
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        final color = span.style?.color;
        if (color != null && color.a < 1) faded = color;
        span.children?.forEach(walk);
      }
    }

    walk(tester.widget<RichText>(find.byType(RichText).first).text);
    expect(faded, isNull);
  });

  group('callbacks', () {
    testWidgets('onComplete fires once after streaming, not for history', (
      tester,
    ) async {
      var completed = 0;
      final texts = <String>[];
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
            onComplete: () => completed++,
            onTextChanged: texts.add,
          ),
        ),
      );
      controller.append('One');
      await tester.pump();
      controller.append(' two');
      await tester.pump();
      expect(completed, 0);
      controller.complete();
      await tester.pump();
      await tester.pump();
      expect(completed, 1);
      expect(texts, ['', 'One', 'One two']);

      var historyCompleted = 0;
      await tester.pumpWidget(
        _host(
          StreamingMarkdown.text(
            'Old reply',
            onComplete: () => historyCompleted++,
          ),
        ),
      );
      await tester.pump();
      expect(historyCompleted, 0);
    });
  });
}
