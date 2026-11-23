import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/renderer.dart';

Widget _host(String text, {VoidCallback? onComplete}) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => StreamingMarkdown.text(
    text,
    isComplete: false,
    completeAfter: const Duration(seconds: 1),
    smoothing: const Smoothing.none(),
    onComplete: onComplete,
  ),
);

void main() {
  testWidgets('a reply from the history shows no cursor', (tester) async {
    var completed = 0;
    await tester.pumpWidget(
      _host('Old **reply**', onComplete: () => completed++),
    );
    await tester.pump();
    expect(find.byType(StreamingCursor), findsNothing);
    expect(find.textContaining('reply', findRichText: true), findsOneWidget);
    expect(completed, 0);
  });

  testWidgets('a growing reply streams, then completes when it stops', (
    tester,
  ) async {
    var completed = 0;
    void done() => completed++;
    await tester.pumpWidget(_host('Hel', onComplete: done));
    await tester.pumpWidget(_host('Hello wor', onComplete: done));
    await tester.pump();
    expect(find.byType(StreamingCursor), findsOneWidget);
    expect(
      find.textContaining('Hello wor', findRichText: true),
      findsOneWidget,
    );

    // Still growing before the pause runs out: still streaming.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_host('Hello world', onComplete: done));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(StreamingCursor), findsOneWidget);
    expect(completed, 0);

    // A second with no growth: complete.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(StreamingCursor), findsNothing);
    expect(completed, 1);
    expect(
      find.textContaining('Hello world', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a reply that grows again after completing streams again', (
    tester,
  ) async {
    await tester.pumpWidget(_host('One'));
    await tester.pumpWidget(_host('One two'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(StreamingCursor), findsNothing);
    await tester.pumpWidget(_host('One two three'));
    await tester.pump();
    expect(find.byType(StreamingCursor), findsOneWidget);
    expect(find.textContaining('three', findRichText: true), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(StreamingCursor), findsNothing);
  });

  testWidgets('other text replaces the reply, complete', (tester) async {
    await tester.pumpWidget(_host('First'));
    await tester.pumpWidget(_host('First and more'));
    await tester.pumpWidget(_host('Something else'));
    await tester.pump();
    expect(find.byType(StreamingCursor), findsNothing);
    expect(
      find.textContaining('Something else', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('First', findRichText: true), findsNothing);
  });

  testWidgets('removing the widget mid-reply leaves no timer', (tester) async {
    await tester.pumpWidget(_host('A'));
    await tester.pumpWidget(_host('AB'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
