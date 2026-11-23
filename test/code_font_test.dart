import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';

void main() {
  testWidgets('code is drawn without ligatures, so <| stays two characters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: StreamingMarkdown.text(
          'Inline `a != b` and a block:\n\n```dart\nA <|-- B -> c\n```\n',
        ),
      ),
    );
    // every span of code text has the ligature features turned off
    final spans = <TextStyle>[];
    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      text.text.visitChildren((span) {
        final style = span.style;
        final words = span is TextSpan ? span.text ?? '' : '';
        if (style != null && (words.contains('<|') || words.contains('!='))) {
          spans.add(style);
        }
        return true;
      });
    }
    expect(spans, isNotEmpty);
    for (final style in spans) {
      expect(style.fontFeatures, contains(const FontFeature.disable('calt')));
    }
  });
}
