import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  pageRouteBuilder: <T>(settings, builder) =>
      PageRouteBuilder<T>(pageBuilder: (context, _, _) => builder(context)),
  home: DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: Padding(padding: const EdgeInsets.only(top: 120), child: child),
  ),
);

void main() {
  testWidgets('long press selects a word and shows the menu with actions', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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
    String? asked;
    final changes = <String>[];
    await tester.pumpWidget(
      _app(
        MarkdownSelectionArea(
          onSelectionChanged: changes.add,
          actions: [
            MarkdownSelectionAction(
              label: 'Ask about this',
              onSelected: (text) => asked = text,
            ),
          ],
          child: const StreamingMarkdown.text('Streaming **markdown** rocks.'),
        ),
      ),
    );
    expect(find.text('Copy'), findsNothing);

    await tester.longPressAt(
      tester.getTopLeft(find.byType(RichText)) + const Offset(30, 8),
    );
    await tester.pumpAndSettle();
    expect(changes.last, 'Streaming');
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);

    await tester.tap(find.text('Ask about this'));
    await tester.pumpAndSettle();
    expect(asked, 'Streaming');
    expect(find.text('Ask about this'), findsNothing);

    // select everything, then copy it: plain text, without the ** marks
    await tester.longPressAt(
      tester.getTopLeft(find.byType(RichText)) + const Offset(30, 8),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(changes.last, 'Streaming markdown rocks.');
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'Streaming markdown rocks.');
  });

  testWidgets('labels can be translated', (tester) async {
    await tester.pumpWidget(
      _app(
        const MarkdownSelectionArea(
          copyLabel: 'નકલ કરો',
          selectAllLabel: 'બધું પસંદ કરો',
          child: StreamingMarkdown.text('Hello there.'),
        ),
      ),
    );
    await tester.longPressAt(
      tester.getTopLeft(find.byType(RichText)) + const Offset(20, 8),
    );
    await tester.pumpAndSettle();
    expect(find.text('નકલ કરો'), findsOneWidget);
    expect(find.text('બધું પસંદ કરો'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
  });
}
