import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_client/llm_client.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_client/llm_markdown_client.dart';

const call = LlmToolCall(
  id: 'c1',
  name: 'get_weather',
  arguments: {'city': 'Paris'},
);

List<LlmEvent> reply() => const [
  LlmThinkingDelta('Checking.'),
  LlmToolCallStart('c1', 'get_weather'),
  LlmToolCallDelta('c1', {'city': 'Pa'}, '{"city": "Pa'),
  LlmToolCallDelta('c1', {'city': 'Paris'}, 'ris"}'),
  LlmToolCallDone(call),
  LlmTextDelta('It is **18 °C**'),
  LlmTextDelta(' today.'),
  LlmUsage(inputTokens: 5, outputTokens: 7),
  LlmDone(LlmFinishReason.stop),
];

void main() {
  test('text, thinking and tool calls reach the controller', () async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    final seen = <LlmEvent>[];
    await controller.addLlmEvents(
      Stream.fromIterable(reply()),
      onEvent: seen.add,
    );
    expect(controller.text, 'It is **18 °C** today.');
    expect(controller.thinking, 'Checking.');
    expect(controller.isComplete, isTrue);
    expect(controller.error, isNull);
    final tool = controller.toolCalls.single;
    expect(tool.name, 'get_weather');
    expect(tool.arguments, '{"city": "Paris"}');
    expect(tool.summary, 'Paris');
    expect(tool.isDone, isTrue);
    expect(seen, hasLength(reply().length));
    expect(seen.whereType<LlmUsage>().single.outputTokens, 7);
  });

  test('arguments show while they are written', () async {
    final events = StreamController<LlmEvent>();
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    final done = controller.addLlmEvents(events.stream);
    events
      ..add(const LlmToolCallStart('c1', 'search'))
      ..add(const LlmToolCallDelta('c1', {'q': 'dart st'}, '{"q": "dart st'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.toolCalls.single.isDone, isFalse);
    expect(controller.toolCalls.single.summary, 'dart st');
    // the call is marked done when its Done event comes, before the reply
    // ends
    events
      ..add(const LlmToolCallStart('c2', 'other'))
      ..add(const LlmToolCallDone(LlmToolCall(id: 'c2', name: 'other')));
    await Future<void>.delayed(Duration.zero);
    expect(controller.toolCalls.map((c) => c.isDone), [false, true]);
    await events.close();
    await done;
    // a call the stream never finished is finished with the reply
    expect(controller.toolCalls.every((c) => c.isDone), isTrue);
  });

  test('an error ends the reply with it and is rethrown', () async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    final done = controller.addLlmEvents(
      Stream<LlmEvent>.multi((c) {
        c.add(const LlmTextDelta('Part'));
        c.addError(const LlmException('Rate limit', statusCode: 429));
      }),
    );
    await expectLater(done, throwsA(isA<LlmException>()));
    expect(controller.text, 'Part');
    expect(controller.isComplete, isTrue);
    expect('${controller.error}', contains('Rate limit'));
  });

  test('stop (complete) or reset cancels the request at once', () async {
    for (final stop in [
      (StreamingMarkdownController c) => c.complete(),
      (StreamingMarkdownController c) => c.reset(),
    ]) {
      var cancelled = false;
      final events = StreamController<LlmEvent>(
        onCancel: () => cancelled = true,
      );
      final controller = StreamingMarkdownController();
      final done = controller.addLlmEvents(events.stream);
      events.add(const LlmTextDelta('Hello'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.text, 'Hello');
      stop(controller);
      await done;
      expect(cancelled, isTrue);
      expect(events.hasListener, isFalse);
      expect(controller.error, isNull);
      controller.dispose();
      await events.close();
    }
  });

  test(
    'a reply started after reset is not touched by the old stream',
    () async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      final old = StreamController<LlmEvent>();
      final first = controller.addLlmEvents(old.stream);
      controller.reset();
      await first;
      await controller.addLlmEvents(
        Stream.fromIterable(const [LlmTextDelta('New')]),
      );
      old.add(const LlmTextDelta('Old'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.text, 'New');
      await old.close();
    },
  );

  test('an error thrown by onEvent ends the reply too', () async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await expectLater(
      controller.addLlmEvents(
        Stream.fromIterable(const [LlmTextDelta('a')]),
        onEvent: (_) => throw StateError('bad handler'),
      ),
      throwsStateError,
    );
    expect(controller.error, isA<StateError>());
  });
}
