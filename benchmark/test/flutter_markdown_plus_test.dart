import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_benchmark/bench.dart';

void main() {
  testWidgets('flutter_markdown_plus', (tester) async {
    final result = await run(
      tester,
      'flutter_markdown_plus',
      sampleReply(),
      // the usual way: rebuild MarkdownBody with the whole text so far
      (soFar, done) => tester.pumpWidget(host(MarkdownBody(data: soFar))),
    );
    // ignore: avoid_print
    print('RESULT $result');
  });
}
