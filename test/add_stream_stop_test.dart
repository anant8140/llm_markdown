import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

void main() {
  test('complete (a stop button) cancels addStream at once', () async {
    var cancelled = false;
    final source = StreamController<String>(onCancel: () => cancelled = true);
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    final done = controller.addStream(source.stream);
    source.add('Hello');
    await Future<void>.delayed(Duration.zero);
    controller.complete();
    await done;
    expect(cancelled, isTrue);
    expect(controller.text, 'Hello');
    expect(controller.error, isNull);
    await source.close();
  });

  test('reset cancels addStream without waiting for a chunk', () async {
    var cancelled = false;
    final source = StreamController<String>(onCancel: () => cancelled = true);
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    final done = controller.addStream(source.stream);
    controller.reset('Other');
    await done;
    expect(cancelled, isTrue);
    expect(controller.text, 'Other');
    expect(controller.isComplete, isFalse);
    await source.close();
  });

  test('a reply stopped before its stream starts cancels it quietly', () async {
    var cancelled = false;
    final source = StreamController<String>(onCancel: () => cancelled = true);
    final controller = StreamingMarkdownController()..append('Hi');
    addTearDown(controller.dispose);
    controller.complete();
    await controller.addStream(source.stream);
    expect(cancelled, isTrue);
    expect(controller.text, 'Hi');
    expect(controller.error, isNull);
    await source.close();
  });

  test('adapters on a stopped reply close the response quietly', () async {
    for (final read
        in <
          Future<void> Function(StreamingMarkdownController, Stream<List<int>>)
        >[
          (c, b) => c.addOpenAIStream(b),
          (c, b) => c.addAnthropicStream(b),
          (c, b) => c.addGeminiStream(b),
          (c, b) => c.addOllamaStream(b),
        ]) {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final controller = StreamingMarkdownController()..complete();
      await read(controller, body.stream);
      expect(cancelled, isTrue);
      expect(controller.error, isNull);
      controller.dispose();
      await body.close();
    }
  });
}
