import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_example/full_stack.dart';
import 'package:material_ui/material_ui.dart';
import 'package:server_sent_events/testing.dart';

Future<void> settle(WidgetTester tester, [int rounds = 30]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('a reply goes from the API to the screen', (tester) async {
    final fake = FakeSseClient(
      (request) => FakeSseResponse.events(demoEvents()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FullStackDemo(provider: fakeProvider(client: fake)),
      ),
    );
    await tester.tap(find.text('Ask'));
    await settle(tester);

    // the request llm_client made
    expect(fake.requests.single.url.path, endsWith('/chat/completions'));
    expect(fake.bodies.single, contains('"get_weather"'));
    expect(fake.bodies.single, contains('What is the weather in Paris?'));
    // the tool call, with its arguments read by partial_json
    expect(
      find.textContaining('Used get weather', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Paris, France', findRichText: true),
      findsOneWidget,
    );
    // the Markdown reply, drawn by llm_markdown
    expect(
      find.textContaining('Paris today', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('18 °C', findRichText: true), findsOneWidget);
    expect(find.textContaining('12 km/h', findRichText: true), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
  });

  testWidgets('Stop ends the reply and aborts the request', (tester) async {
    final fake = FakeSseClient(
      (request) =>
          FakeSseResponse.events(demoEvents().take(3).toList(), keepOpen: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FullStackDemo(provider: fakeProvider(client: fake)),
      ),
    );
    await tester.tap(find.text('Ask'));
    await settle(tester, 10);
    expect(
      find.textContaining('Using get weather', findRichText: true),
      findsOneWidget,
    );
    expect(fake.aborted, 0);
    await tester.tap(find.text('Stop'));
    await settle(tester, 10);
    expect(fake.aborted, 1);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.byType(StreamingMarkdown), findsOneWidget);
  });
}
