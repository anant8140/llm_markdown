import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_benchmark/bench.dart';

void main() {
  testWidgets('llm_markdown', (tester) async {
    final controller = StreamingMarkdownController();
    var shown = '';
    await tester.pumpWidget(
      host(
        StreamingMarkdown(
          controller: controller,
          smoothing: const Smoothing.none(),
        ),
      ),
    );
    final result = await run(tester, 'llm_markdown', sampleReply(), (
      soFar,
      done,
    ) async {
      if (soFar.length > shown.length) {
        controller.append(soFar.substring(shown.length));
        shown = soFar;
      }
      if (done) controller.complete();
    });
    // ignore: avoid_print
    print('RESULT $result');
  });
}
