import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

void main() {
  testWidgets('HTML b, i, s and code tags are drawn like Markdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF2196F3),
        builder: (context, _) => const StreamingMarkdown.text(
          'A <b>bold</b>, <i>slanted</i>, <s>gone</s> and <code>x</code>.',
        ),
      ),
    );
    await tester.pump();
    final text = tester.widget<RichText>(
      find.textContaining('bold', findRichText: true),
    );
    final styles = <String, TextStyle?>{};
    text.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        styles[span.text!] = span.style;
      }
      return true;
    });
    // the tags themselves are not shown
    expect(text.text.toPlainText(), 'A bold, slanted, gone and x.');
    TextStyle? of(String word) {
      // the style of the span, with its parents' merged in by the renderer
      TextStyle? found;
      void walk(InlineSpan span, TextStyle? inherited) {
        if (span is! TextSpan) return;
        final merged = inherited?.merge(span.style) ?? span.style;
        if (span.text == word) found = merged;
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child, merged);
        }
      }

      walk(text.text, null);
      return found;
    }

    expect(of('bold')?.fontWeight, FontWeight.w700);
    expect(of('slanted')?.fontStyle, FontStyle.italic);
    expect(of('gone')?.decoration, TextDecoration.lineThrough);
    expect(of('x')?.fontFamily, isNotNull);
    expect(styles, isNotEmpty);
  });
}
