import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/code_block.dart' show highlightJobs;

void main() {
  testWidgets(
    'a streaming block in a language without a grammar is tried once per line',
    (tester) async {
      Widget reply(String text) => Directionality(
        textDirection: TextDirection.ltr,
        child: StreamingMarkdown.text(
          text,
          isComplete: false,
          smoothing: const Smoothing.none(),
          codeBlocks: const CodeBlockOptions(highlightWhileStreaming: true),
        ),
      );
      // waits long enough for every background job to answer
      Future<void> settle() async {
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
      }

      final before = highlightJobs;
      await tester.pumpWidget(reply('```mermaid\nflowchart TD\n  A[New'));
      // let the background jobs run and answer
      await settle();
      // one job for the one complete line; it gave nothing, and the same
      // text is not tried again (before, this looped forever, and froze
      // the page on the web)
      expect(highlightJobs - before, 1);

      // a new complete line is tried once more
      await tester.pumpWidget(
        reply('```mermaid\nflowchart TD\n  A[New] --> B\n  B'),
      );
      await settle();
      expect(highlightJobs - before, 2);
    },
  );
}
