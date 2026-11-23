import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_example/main.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('a visitor streams their own Markdown, at any speed', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    // the sample reply looks something up first
    expect(find.text('Using web search…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Used web search'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.speed));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('All at once').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byType(TextField),
      '# Hi there\n\nA **bold** move.',
    );
    await tester.tap(find.text('Stream it'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Your Markdown'), findsOneWidget);
    expect(find.textContaining('Hi there', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('bold move', findRichText: true),
      findsOneWidget,
    );
    // only the sample reply has the web search
    expect(find.text('Used web search'), findsNothing);
  });
}
