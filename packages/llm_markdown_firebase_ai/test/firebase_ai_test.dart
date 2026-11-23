import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
// not exported by firebase_ai; responses carry it, tests build it
// ignore: implementation_imports
import 'package:firebase_ai/src/api.dart' show GroundingMetadata;
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_firebase_ai/llm_markdown_firebase_ai.dart';

GenerateContentResponse _reply(
  List<Part> parts, {
  FinishReason? finish,
  List<GroundingChunk>? sources,
}) => GenerateContentResponse([
  Candidate(
    Content('model', parts),
    null,
    null,
    finish,
    null,
    groundingMetadata: sources == null
        ? null
        : GroundingMetadata(
            groundingChunks: sources,
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
}
