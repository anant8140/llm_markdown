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
}
