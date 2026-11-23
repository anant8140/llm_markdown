import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

Widget _host(Widget child) =>
    WidgetsApp(color: const Color(0xFF2196F3), builder: (context, _) => child);

void main() {
  test('argumentsSoFar reads arguments that are still being written', () {
    const call = MarkdownToolCall(
      id: '1',
      name: 'web_search',
      arguments: '{"query": "Paris wea',
    );
    expect(call.argumentsSoFar, {'query': 'Paris wea'});
    expect(call.summary, 'Paris wea');
  });

  test('summary: the first text among the arguments, on one line', () {
    MarkdownToolCall call(String arguments) =>
        MarkdownToolCall(id: '1', name: 't', arguments: arguments);
    expect(call('{"limit": 5, "q": " two\\n lines "}').summary, 'two lines');
    expect(call('["", "first"]').summary, 'first');
    expect(call('{"limit": 5}').summary, isNull);
    expect(call('').summary, isNull);
    expect(call('   ').argumentsSoFar, isNull);
    // not JSON: no summary, and no error
    expect(call('query=Paris').summary, isNull);
    expect(call('{"a" 1}').argumentsSoFar, isNull);
  });

  testWidgets('the tool line shows what the call is about, as it is written', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(StreamingMarkdown(controller: controller)));
    controller.startToolCall('1', 'web_search');
    await tester.pump();
    expect(
      find.textContaining('Using web search', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Paris', findRichText: true), findsNothing);

    controller.addToolCallArguments('1', '{"query": "Paris wea');
    await tester.pump();
    expect(
      find.textContaining('Paris wea', findRichText: true),
      findsOneWidget,
    );

    controller.addToolCallArguments('1', 'ther"}');
    controller.finishToolCall('1');
    await tester.pump();
    final line = find.textContaining('Used web search', findRichText: true);
    expect(line, findsOneWidget);
    expect(
      find.textContaining('Paris weather', findRichText: true),
      findsOneWidget,
    );
    // one line, cut with an ellipsis when long
    final text = tester.widget<RichText>(line);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    controller.complete();
    await tester.pump();
  });

  testWidgets('showToolCallArguments: false keeps only the label', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StreamingMarkdown(controller: controller, showToolCallArguments: false),
      ),
    );
    controller.startToolCall('1', 'web_search');
    controller.addToolCallArguments('1', '{"query": "secret"}');
    await tester.pump();
    expect(
      find.textContaining('Using web search', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('secret', findRichText: true), findsNothing);
    controller.complete();
    await tester.pump();
  });
}
