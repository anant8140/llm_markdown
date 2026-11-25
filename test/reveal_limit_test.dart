import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

Widget _host(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: SingleChildScrollView(child: child),
  ),
);

/// Pumps a [StreamingMarkdown] on [controller] limited by [limit] and
/// returns a getter for the text it last reported as shown.
Future<String Function()> _pumpLimited(
  WidgetTester tester,
  StreamingMarkdownController controller,
  ValueListenable<int>? limit, {
  Smoothing smoothing = const Smoothing.none(),
  bool tapToSkip = false,
  Duration updateInterval = Duration.zero,
  VoidCallback? onComplete,
}) async {
  var visible = '';
  await tester.pumpWidget(
    _host(
      StreamingMarkdown(
        controller: controller,
        revealLimit: limit,
        smoothing: smoothing,
        tapToSkip: tapToSkip,
        updateInterval: updateInterval,
        onComplete: onComplete,
        onTextChanged: (text) => visible = text,
      ),
    ),
  );
  await tester.pump();
  return () => visible;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _reply = 'One two three. Four five six. Seven eight nine.';

void main() {
  late StreamingMarkdownController controller;
  late ValueNotifier<int> limit;

  setUp(() {
    controller = StreamingMarkdownController();
    limit = ValueNotifier(0);
  });
  tearDown(() {
    controller.dispose();
    limit.dispose();
  });

  testWidgets('shows text only up to the limit, and more as it grows', (
    tester,
  ) async {
    final shown = await _pumpLimited(tester, controller, limit);
    controller.append(_reply);
    await tester.pump();
    await tester.pump();
    expect(shown(), '');

    limit.value = 14;
    await tester.pump();
    await tester.pump();
    expect(shown(), 'One two three.');

    limit.value = 29;
    await tester.pump();
    await tester.pump();
    expect(shown(), 'One two three. Four five six.');
  });

  testWidgets('smoothing reveals up to the limit and stops there', (
    tester,
  ) async {
    final shown = await _pumpLimited(
      tester,
      controller,
      limit,
      smoothing: const Smoothing.adaptive(),
    );
    limit.value = 14;
    controller.append(_reply);
    await _settle(tester);
    expect(shown(), 'One two three.');

    limit.value = 29;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(shown().length, inInclusiveRange(15, 28), reason: 'still smooth');
    await _settle(tester);
    expect(shown(), 'One two three. Four five six.');
  });

  testWidgets('word by word does not pass a limit inside a word', (
    tester,
  ) async {
    final shown = await _pumpLimited(
      tester,
      controller,
      limit,
      smoothing: const Smoothing.wordByWord(),
    );
    limit.value = 6; // inside "two"
    controller.append(_reply);
    await _settle(tester);
    expect(shown(), 'One tw');
  });

  testWidgets('no limit, or null later, shows the rest as usual', (
    tester,
  ) async {
    final shown = await _pumpLimited(tester, controller, null);
    controller.append(_reply);
    await tester.pump();
    await tester.pump();
    expect(shown(), _reply);

    controller.reset();
    limit.value = 3;
    final limited = await _pumpLimited(tester, controller, limit);
    controller.append(_reply);
    await tester.pump();
    await tester.pump();
    expect(limited(), 'One');

    // the user turns the voice off in the middle of the reply
    final again = await _pumpLimited(tester, controller, null);
    await tester.pump();
    expect(again(), _reply);
  });

  testWidgets('text already there when it first builds keeps to the limit', (
    tester,
  ) async {
    controller.append(_reply);
    limit.value = 3;
    final shown = await _pumpLimited(tester, controller, limit);
    expect(shown(), 'One');
  });

  testWidgets('lowering the limit hides text again, even while paused', (
    tester,
  ) async {
    limit.value = 29;
    final shown = await _pumpLimited(tester, controller, limit);
    controller.append(_reply);
    await tester.pump();
    await tester.pump();
    expect(shown(), 'One two three. Four five six.');

    controller.pause();
    limit.value = 14;
    await tester.pump();
    await tester.pump();
    expect(shown(), 'One two three.');
  });

  testWidgets('a limit inside a letter shows the whole letter', (tester) async {
    const text = 'Hi 👋🏽 there';
    final shown = await _pumpLimited(tester, controller, limit);
    controller.append(text);
    limit.value = 4; // inside the waving hand
    await tester.pump();
    await tester.pump();
    expect(shown(), 'Hi 👋🏽');
  });

  testWidgets('skipAnimation and a tap show everything and lift the limit', (
    tester,
  ) async {
    limit.value = 3;
    final shown = await _pumpLimited(tester, controller, limit);
    controller.append('One two. ');
    await tester.pump();
    await tester.pump();
    expect(shown(), 'One');

    controller.skipAnimation();
    await tester.pump();
    await tester.pump();
    expect(shown(), 'One two. ');
    controller.append('Three.');
    await tester.pump();
    await tester.pump();
    expect(shown(), 'One two. Three.', reason: 'stays lifted');

    // replacing the text brings the limit back
    controller.reset('Four five.');
    await tester.pump();
    await tester.pump();
    expect(shown(), 'Fou');

    final tapped = await _pumpLimited(
      tester,
      controller,
      limit,
      tapToSkip: true,
    );
    await tester.tap(find.byType(StreamingMarkdown));
    await tester.pump();
    await tester.pump();
    expect(tapped(), 'Four five.');
    controller.append(' Six.');
    await tester.pump();
    await tester.pump();
    expect(tapped(), 'Four five. Six.', reason: 'a tap lifts it too');

    // replaying brings it back too
    controller.replay();
    await tester.pump();
    await tester.pump();
    expect(tapped(), 'Fou');
  });

  testWidgets('onComplete waits until the limit reaches the end', (
    tester,
  ) async {
    var completed = 0;
    await _pumpLimited(
      tester,
      controller,
      limit,
      onComplete: () => completed++,
    );
    controller
      ..append('Short reply.')
      ..complete();
    limit.value = 5;
    await tester.pump();
    await tester.pump();
    expect(completed, 0);

    limit.value = 12;
    await tester.pump();
    await tester.pump();
    expect(completed, 1);
  });

  testWidgets('works with updateInterval', (tester) async {
    final shown = await _pumpLimited(
      tester,
      controller,
      limit,
      updateInterval: const Duration(milliseconds: 100),
    );
    controller.append(_reply);
    limit.value = 14;
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(shown(), 'One two three.');
  });

  testWidgets('a new listenable is followed and the old one is let go', (
    tester,
  ) async {
    final first = _CountedLimit(0);
    final other = _CountedLimit(29);
    addTearDown(first.dispose);
    addTearDown(other.dispose);
    final shown = await _pumpLimited(tester, controller, first);
    controller.append(_reply);
    await tester.pump();
    expect(shown(), '');

    final switched = await _pumpLimited(tester, controller, other);
    await tester.pump();
    expect(switched(), 'One two three. Four five six.');
    expect(first.listeners, 0);
    expect(other.listeners, 1);
    first.value = 3; // the old one no longer matters
    await tester.pump();
    await tester.pump();
    expect(switched(), 'One two three. Four five six.');

    await tester.pumpWidget(const SizedBox());
    expect(other.listeners, 0);
    other.value = 40; // after dispose: no setState on a dead widget
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('works with StreamingMarkdown.stream', (tester) async {
    final source = StreamController<String>();
    var visible = '';
    limit.value = 7;
    await tester.pumpWidget(
      _host(
        StreamingMarkdown.stream(
          source.stream,
          revealLimit: limit,
          smoothing: const Smoothing.none(),
          onTextChanged: (text) => visible = text,
        ),
      ),
    );
    source.add(_reply);
    await tester.pump();
    await tester.pump();
    expect(visible, 'One two');
    await source.close();
  });
}

class _CountedLimit extends ValueNotifier<int> {
  _CountedLimit(super.value);

  int listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }
}
