import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
// not exported by firebase_ai; responses carry it, tests build it
// ignore: implementation_imports
import 'package:firebase_ai/src/api.dart'
    show CodeLanguage, GroundingMetadata, Outcome, SearchEntryPoint;
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_firebase_ai/llm_markdown_firebase_ai.dart';

GenerateContentResponse _reply(
  List<Part> parts, {
  FinishReason? finish,
  List<GroundingChunk>? sources,
  String? suggestions,
}) => GenerateContentResponse([
  Candidate(
    Content('model', parts),
    null,
    null,
    finish,
    null,
    groundingMetadata: sources == null && suggestions == null
        ? null
        : GroundingMetadata(
            searchEntryPoint: suggestions == null
                ? null
                : SearchEntryPoint(renderedContent: suggestions),
            groundingChunks: sources ?? const [],
            groundingSupports: const [],
            webSearchQueries: const [],
          ),
  ),
], null);

GroundingChunk _page(String uri, String title) => GroundingChunk(
  web: WebGroundingChunk(uri: uri, title: title),
);

void main() {
  test(
    'appends text, thinking, tool calls and sources, then completes',
    () async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await controller.addFirebaseAIStream(
        Stream.fromIterable([
          _reply([const TextPart('Checking the docs', isThought: true)]),
          _reply([
            const FunctionCall('web_search', {'query': 'dart'}, id: 'a1'),
            const FunctionCall('open_page', {}),
          ]),
          _reply(
            [const TextPart('# Dart\n\nIt is ')],
            sources: [
              _page('https://dart.dev', 'Dart'),
              _page('https://dart.dev', 'Dart'),
              GroundingChunk(),
            ],
          ),
          _reply([
            const TextPart('fast.'),
            const TextPart(''),
          ], finish: FinishReason.stop),
        ]),
      );
      expect(controller.text, '# Dart\n\nIt is fast.');
      expect(controller.thinking, 'Checking the docs');
      expect(controller.isComplete, isTrue);
      expect(controller.error, isNull);
      expect(controller.toolCalls.map((c) => c.id), ['a1', 'call_0']);
      expect(controller.toolCalls.map((c) => c.name), [
        'web_search',
        'open_page',
      ]);
      expect(controller.toolCalls.first.arguments, '{"query":"dart"}');
      expect(controller.toolCalls.last.arguments, '');
      expect(controller.toolCalls.every((c) => c.isDone), isTrue);
      expect(controller.sources.map((s) => s.url), ['https://dart.dev']);
      expect(controller.sources.single.title, 'Dart');
    },
  );

  test('code the model ran, and its output, become code blocks', () async {
    final parts = [
      const TextPart('Let me compute.'),
      ExecutableCodePart(language: CodeLanguage.python, code: 'print(2 ** 10)'),
      CodeExecutionResultPart(outcome: Outcome.ok, output: 'a ``` b\n'),
      const TextPart('It is 1024.'),
    ];
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await controller.addFirebaseAIStream(Stream.value(_reply(parts)));
    expect(
      controller.text,
      'Let me compute.\n\n```python\nprint(2 ** 10)\n```\n\n'
      '\n\n````text\na ``` b\n````\n\nIt is 1024.',
    );

    final hidden = StreamingMarkdownController();
    addTearDown(hidden.dispose);
    await hidden.addFirebaseAIStream(
      Stream.value(_reply(parts)),
      showCodeExecution: false,
    );
    expect(hidden.text, 'Let me compute.It is 1024.');
  });

  test('search suggestions are handed over once per different one', () async {
    final seen = <String>[];
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await controller.addFirebaseAIStream(
      Stream.fromIterable([
        _reply([const TextPart('a')], suggestions: '<div>one</div>'),
        _reply([const TextPart('b')], suggestions: '<div>one</div>'),
        _reply([const TextPart('c')], suggestions: ''),
        _reply([const TextPart('d')], suggestions: '<div>two</div>'),
      ]),
      onSearchSuggestions: seen.add,
    );
    expect(seen, ['<div>one</div>', '<div>two</div>']);
    expect(controller.text, 'abcd');
  });

  test('a blocked prompt ends the reply with an error', () async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    final done = controller.addFirebaseAIStream(
      Stream.value(
        GenerateContentResponse(
          const [],
          PromptFeedback(BlockReason.safety, 'not allowed', const []),
        ),
      ),
    );
    await expectLater(done, throwsA(isA<ModelStreamError>()));
    expect(controller.isComplete, isTrue);
    expect('${controller.error}', contains('Blocked: safety (not allowed)'));
  });

  test(
    'a reply stopped for safety keeps its text and shows the error',
    () async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      final done = controller.addFirebaseAIStream(
        Stream.fromIterable([
          _reply([const TextPart('Part one. ')]),
          _reply(const [], finish: FinishReason.safety),
          _reply([const TextPart('never shown')]),
        ]),
      );
      await expectLater(done, throwsA(isA<ModelStreamError>()));
      expect(controller.text, 'Part one. ');
      expect('${controller.error}', contains('Blocked: safety'));
    },
  );

  test('a FirebaseAIException becomes a ModelStreamError', () async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    final done = controller.addFirebaseAIStream(
      Stream.error(FirebaseAIException('quota exceeded')),
    );
    await expectLater(
      done,
      throwsA(
        isA<ModelStreamError>().having(
          (e) => '$e',
          'text',
          contains('quota exceeded'),
        ),
      ),
    );
    expect(controller.isComplete, isTrue);
  });

  test('stop (complete) or reset cancels the request at once', () async {
    for (final stop in [
      (StreamingMarkdownController c) => c.complete(),
      (StreamingMarkdownController c) => c.reset(),
    ]) {
      var cancelled = false;
      final source = StreamController<GenerateContentResponse>(
        onCancel: () => cancelled = true,
      );
      final controller = StreamingMarkdownController();
      final done = controller.addFirebaseAIStream(source.stream);
      source.add(_reply([const TextPart('Hello')]));
      await Future<void>.delayed(Duration.zero);
      expect(controller.text, 'Hello');
      stop(controller);
      await done;
      expect(cancelled, isTrue);
      expect(source.hasListener, isFalse);
      expect(controller.error, isNull);
      controller.dispose();
      await source.close();
    }
  });

  test(
    'a later reply started with reset is not completed by an old one',
    () async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      final old = StreamController<GenerateContentResponse>();
      final first = controller.addFirebaseAIStream(old.stream);
      controller.reset();
      await first;
      final next = controller.addFirebaseAIStream(
        Stream.value(_reply([const TextPart('New')])),
      );
      old.add(_reply([const TextPart('Old')]));
      await next;
      expect(controller.text, 'New');
      await old.close();
    },
  );

  test('every blocking finish reason ends with an error', () async {
    for (final reason in [
      FinishReason.blocklist,
      FinishReason.prohibitedContent,
      FinishReason.spii,
      FinishReason.malformedFunctionCall,
    ]) {
      final controller = StreamingMarkdownController();
      final done = controller.addFirebaseAIStream(
        Stream.value(_reply(const [], finish: reason)),
      );
      await expectLater(done, throwsA(isA<ModelStreamError>()));
      expect('${controller.error}', contains('Blocked: ${reason.name}'));
      controller.dispose();
    }
    // a normal end is not an error
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await controller.addFirebaseAIStream(
      Stream.value(
        _reply([const TextPart('ok')], finish: FinishReason.maxTokens),
      ),
    );
    expect(controller.error, isNull);
  });

  test('a reply stopped before the first response cancels quietly', () async {
    var cancelled = false;
    final source = StreamController<GenerateContentResponse>(
      onCancel: () => cancelled = true,
    );
    final controller = StreamingMarkdownController()..complete();
    addTearDown(controller.dispose);
    await controller.addFirebaseAIStream(source.stream);
    expect(cancelled, isTrue);
    expect(controller.error, isNull);
    await source.close();
  });
}
