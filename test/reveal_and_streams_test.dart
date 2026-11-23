import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/renderer.dart';
import 'package:llm_markdown/src/smoothing.dart';

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

Stream<List<int>> _body(String text, {int chunk = 7}) async* {
  final bytes = utf8.encode(text);
  for (var i = 0; i < bytes.length; i += chunk) {
    yield bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk);
  }
}

void main() {
  group('reveal controls', () {
    testWidgets('pause holds new text until resume', (tester) async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
          ),
        ),
      );
      controller
        ..append('First. ')
        ..pause()
        ..append('Second.');
      await tester.pump();
      expect(controller.isPaused, isTrue);
      expect(_shown(tester), isNot(contains('Second')));

      controller.resume();
      await tester.pump();
      expect(_shown(tester), contains('Second.'));
    });

    testWidgets('skipAnimation shows everything that arrived', (tester) async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.typewriter(charactersPerSecond: 10),
          ),
        ),
      );
      controller.append('word ' * 50);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_shown(tester).length, lessThan(20));
      controller.skipAnimation();
      await tester.pump();
      expect(_shown(tester), contains('word ' * 49));
    });

    testWidgets('replay reveals a finished reply again', (tester) async {
      final controller = StreamingMarkdownController(
        text: 'A finished reply with several words in it.',
        isComplete: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.typewriter(charactersPerSecond: 40),
          ),
        ),
      );
      expect(_shown(tester), contains('several words'));
      controller.replay();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(_shown(tester), isNot(contains('several words')));
      await tester.pump(const Duration(seconds: 3));
      expect(_shown(tester), contains('several words in it.'));
    });
  });

  group('reveal modes and presets', () {
    test('word boundaries', () {
      const text = 'one two three';
      expect(wordBoundaryAtOrAfter(text, 1, 0, false), 3);
      expect(wordBoundaryAtOrAfter(text, 4, 3, false), 4);
      expect(wordBoundaryAtOrAfter(text, 9, 4, false), 4);
      expect(wordBoundaryAtOrAfter(text, 9, 4, true), text.length);
    });

    testWidgets('wordByWord never shows half a word', (tester) async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.wordByWord(),
            showCursor: false,
          ),
        ),
      );
      const words = ['alpha', 'beta', 'gamma', 'delta', 'epsilon'];
      controller.append('${words.join(' ')} ');
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final shown = _shown(tester).trim();
        if (shown.isEmpty) continue;
        expect(words, contains(shown.split(' ').last), reason: shown);
      }
    });

    test('typewriter keeps its speed, presets differ', () {
      expect(const Smoothing.typewriter().speedFor(5000), 60);
      expect(const Smoothing.adaptive().speedFor(5000), greaterThan(120));
      final presets = {
        const Smoothing.gentle(),
        const Smoothing.fast(),
        const Smoothing.wordByWord(),
        const Smoothing.typewriter(),
        const Smoothing.adaptive(),
      };
      expect(presets, hasLength(5));
      expect(const Smoothing.wordByWord().unit, RevealUnit.word);
    });
  });

  testWidgets('every cursor style draws', (tester) async {
    for (final style in StreamingCursorStyle.values) {
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: StreamingMarkdownController(),
            cursorStyle: style,
          ),
        ),
      );
      final cursor = tester.widget<StreamingCursor>(
        find.byType(StreamingCursor),
      );
      expect(cursor.style, style);
      expect(tester.takeException(), isNull);
    }
    // three dots for the dots style
    expect(
      find.descendant(
        of: find.byType(StreamingCursor),
        matching: find.byType(Container),
      ),
      findsNWidgets(3),
    );
  });

  testWidgets('fadeBottomEdge fades only while streaming', (tester) async {
    final controller = StreamingMarkdownController(text: 'Hi');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(StreamingMarkdown(controller: controller, fadeBottomEdge: true)),
    );
    expect(find.byType(ShaderMask), findsOneWidget);
    await tester.pumpWidget(_host(StreamingMarkdown(controller: controller)));
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('updateInterval batches small chunks', (tester) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
          updateInterval: const Duration(milliseconds: 100),
        ),
      ),
    );
    controller
      ..append('a')
      ..append('b')
      ..append('c');
    await tester.pump(const Duration(milliseconds: 50));
    expect(_shown(tester), isNot(contains('abc')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_shown(tester), contains('abc'));
  });

  group('model streams', () {
    test('server-sent events are split and joined correctly', () async {
      const body =
          ': comment\r\n'
          'event: hello\r\n'
          'data: line one\r\n'
          'data: line two\r\n'
          '\r\n'
          'data: નમસ્તે 🚀\n\n'
          'data:no space\n\n';
      final events = await serverSentEvents(_body(body, chunk: 3)).toList();
      expect(events.map((e) => e.event), ['hello', null, null]);
      expect(events.map((e) => e.data), [
        'line one\nline two',
        'નમસ્તે 🚀',
        'no space',
      ]);
    });

    test('OpenAI chat chunks with reasoning', () async {
      String chunk(Map<String, Object?> delta) =>
          'data: ${jsonEncode({
            'choices': [
              {'delta': delta},
            ],
          })}\n\n';
      final body = [
        chunk({'reasoning_content': 'Think '}),
        chunk({'reasoning_content': 'first.'}),
        chunk({'content': 'Hello'}),
        chunk({'content': ' world'}),
        'data: [DONE]\n\n',
        chunk({'content': 'ignored'}),
      ].join();
      final controller = StreamingMarkdownController();
      await controller.addOpenAIStream(_body(body));
      expect(controller.thinking, 'Think first.');
      expect(controller.text, 'Hello world');
      expect(controller.isComplete, isTrue);
    });

    test('lines that are not JSON are skipped, not fatal', () async {
      String chunk(String content) =>
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': content},
              },
            ],
          })}\n\n';
      // a keep-alive line in the middle, and a connection cut mid-event
      final body = [
        chunk('Hello'),
        'data: ping\n\n',
        chunk(' world'),
        'data: {"choices":[{"del',
      ].join();
      final controller = StreamingMarkdownController();
      await controller.addOpenAIStream(_body(body));
      expect(controller.text, 'Hello world');
      expect(controller.isComplete, isTrue);
      expect(controller.error, isNull);

      final other = StreamingMarkdownController();
      await other.addAnthropicStream(
        _body(
          'data: not json\n\n'
          'data: ${jsonEncode({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': 'Hi'},
          })}\n\n',
        ),
      );
      expect(other.text, 'Hi');
      expect(other.error, isNull);
    });

    test('OpenAI Responses API events', () async {
      final body = [
        for (final e in [
          {'type': 'response.reasoning_summary_text.delta', 'delta': 'Plan'},
          {'type': 'response.output_text.delta', 'delta': 'Hi'},
          {'type': 'response.output_text.delta', 'delta': ' there'},
          {'type': 'response.completed'},
        ])
          'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n',
      ].join();
      final controller = StreamingMarkdownController();
      await controller.addOpenAIStream(_body(body));
      expect((controller.thinking, controller.text), ('Plan', 'Hi there'));
    });

    test('Anthropic text and thinking deltas', () async {
      final body = [
        for (final e in [
          {'type': 'message_start', 'message': <String, Object>{}},
          {
            'type': 'content_block_delta',
            'delta': {'type': 'thinking_delta', 'thinking': 'Hmm.'},
          },
          {
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': 'Answer'},
          },
          {'type': 'message_stop'},
        ])
          'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n',
      ].join();
      final controller = StreamingMarkdownController();
      await controller.addAnthropicStream(_body(body));
      expect((controller.thinking, controller.text), ('Hmm.', 'Answer'));
      expect(controller.isComplete, isTrue);
    });

    test('Gemini parts, thoughts and errors', () async {
      String chunk(List<Map<String, Object?>> parts) =>
          'data: ${jsonEncode({
            'candidates': [
              {
                'content': {'role': 'model', 'parts': parts},
              },
            ],
          })}\r\n\r\n';
      final body = [
        chunk([
          {'text': 'Think', 'thought': true},
        ]),
        chunk([
          {'text': 'ing.', 'thought': true},
          {'text': 'નમ'},
        ]),
        'data: {"candidates": [\n\n',
        chunk([
          {'text': 'સ્તે'},
        ]),
        'data: ${jsonEncode({
          'usageMetadata': {'totalTokenCount': 9},
        })}\r\n\r\n',
      ].join();
      final controller = StreamingMarkdownController();
      await controller.addGeminiStream(_body(body, chunk: 5));
      expect((controller.thinking, controller.text), ('Thinking.', 'નમસ્તે'));
      expect(controller.isComplete, isTrue);

      final failed = StreamingMarkdownController();
      await expectLater(
        failed.addGeminiStream(
          _body(
            'data: ${jsonEncode({
              'error': {'code': 429, 'message': 'Resource exhausted'},
            })}\n\n',
          ),
        ),
        throwsA(isA<ModelStreamError>()),
      );
      expect('${failed.error}', contains('Resource exhausted'));
    });

    test('Gemini without alt=sse: one JSON array, read as it comes', () async {
      Map<String, Object?> item(Object part) => {
        'candidates': [
          {
            'content': {
              'parts': [part],
            },
          },
        ],
      };
      final body = StreamController<List<int>>();
      final controller = StreamingMarkdownController();
      final done = controller.addGeminiStream(body.stream);
      body.add(
        utf8.encode(
          '\n[${jsonEncode(item({'text': 'Plan {x}', 'thought': true}))}',
        ),
      );
      body.add(
        utf8.encode(',\r\n${jsonEncode(item({'text': 'He said "}" and \\'}))}'),
      );
      await pumpEventQueue();
      // shown before the body has ended
      expect(controller.thinking, 'Plan {x}');
      expect(controller.text, r'He said "}" and \');
      final rest = utf8.encode(
        ',\n${jsonEncode(item({'text': ' નમસ્તે'}))}\n]',
      );
      // split inside a character too
      for (var i = 0; i < rest.length; i += 3) {
        body.add(rest.sublist(i, i + 3 > rest.length ? rest.length : i + 3));
      }
      await body.close();
      await done;
      expect(controller.text, r'He said "}" and \ નમસ્તે');
      expect(controller.isComplete, isTrue);
      // a whole generateContent answer, not streamed, works too
      final whole = StreamingMarkdownController();
      await whole.addGeminiStream(
        _body(jsonEncode(item({'text': 'All at once'}))),
      );
      expect(whole.text, 'All at once');
    });

    test('Ollama chat and generate lines', () async {
      final chat = [
        {
          'message': {'role': 'assistant', 'content': '', 'thinking': 'Hmm'},
          'done': false,
        },
        {
          'message': {'role': 'assistant', 'content': 'Hi 🚀'},
          'done': false,
        },
        {
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
        },
        {
          'message': {'role': 'assistant', 'content': 'after done'},
          'done': false,
        },
      ].map(jsonEncode).join('\n');
      final controller = StreamingMarkdownController();
      await controller.addOllamaStream(_body(chat, chunk: 4));
      expect((controller.thinking, controller.text), ('Hmm', 'Hi 🚀'));
      expect(controller.isComplete, isTrue);

      final generate = StreamingMarkdownController();
      await generate.addOllamaStream(
        _body(
          '${jsonEncode({'response': 'One', 'done': false})}\n\n'
          'garbage\n'
          '${jsonEncode({'response': ' two', 'done': false})}',
        ),
      );
      expect(generate.text, 'One two');
      expect(generate.isComplete, isTrue);

      final failed = StreamingMarkdownController();
      await expectLater(
        failed.addOllamaStream(
          _body('${jsonEncode({'error': "model 'x' not found"})}\n'),
        ),
        throwsA(isA<ModelStreamError>()),
      );
      expect('${failed.error}', contains('not found'));
    });

    test('an error event ends the reply with the error', () async {
      final body =
          'data: ${jsonEncode({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': 'Part'},
          })}\n\n'
          'event: error\ndata: ${jsonEncode({
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
          })}\n\n';
      final controller = StreamingMarkdownController();
      await expectLater(
        controller.addAnthropicStream(_body(body)),
        throwsA(isA<ModelStreamError>()),
      );
      expect(controller.text, 'Part');
      expect('${controller.error}', contains('Overloaded'));
    });
  });
}
