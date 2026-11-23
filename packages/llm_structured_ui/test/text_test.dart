import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

import 'helpers.dart';

/// Whether some text span on screen holds [text] in a bold weight.
bool isBold(WidgetTester tester, String text) {
  var found = false;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    void visit(InlineSpan span, FontWeight? inherited) {
      final weight = span.style?.fontWeight ?? inherited;
      if (span is TextSpan) {
        if ((span.text ?? '').contains(text) &&
            weight != null &&
            weight.value >= 600) {
          found = true;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, weight);
        }
      }
    }

    visit(rich.text, null);
  }
  return found;
}

void main() {
  group('StructuredText', () {
    Widget tree(StructuredStreamController c, {bool markdown = false}) =>
        StructuredBuilder(
          controller: c,
          builder: (context, data) =>
              StructuredText(data['title'], markdown: markdown),
        );

    testWidgets('shows the text so far with a cursor, then without', (
      tester,
    ) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      expect(shown(tester), isEmpty);
      expect(cursor, findsNothing);

      await feed(tester, c, '{"title": "Pan');
      expect(shown(tester), ['Pan']);
      expect(cursor, findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);

      await feed(tester, c, 'cak');
      expect(shown(tester), ['Pancak']);
      expect(cursor, findsOneWidget);

      await feed(tester, c, 'es"');
      expect(shown(tester), ['Pancakes']);
      expect(cursor, findsNothing);

      // nothing keeps animating once the field is done
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the cursor blinks', (tester) async {
      final c = StructuredStreamController()..add('{"title": "Pan');
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      double opacity() => tester
          .widget<FadeTransition>(
            find.descendant(of: cursor, matching: find.byType(FadeTransition)),
          )
          .opacity
          .value;
      final seen = <double>{};
      for (var i = 0; i < 12; i++) {
        seen.add(opacity());
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(seen.length, greaterThan(3));
      expect(seen.reduce((a, b) => a < b ? a : b), lessThan(0.3));
    });

    testWidgets('showCursor false shows no cursor', (tester) async {
      final c = StructuredStreamController()..add('{"title": "Pan');
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        StructuredBuilder(
          controller: c,
          builder: (context, data) =>
              StructuredText(data['title'], showCursor: false),
        ),
      );
      expect(shown(tester), ['Pan']);
      expect(cursor, findsNothing);
    });

    testWidgets('with animations disabled the cursor stands still', (
      tester,
    ) async {
      final c = StructuredStreamController()..add('{"title": "Pan');
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c), disableAnimations: true);
      expect(cursor, findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpAndSettle();
      final fade = tester.widget<FadeTransition>(
        find.descendant(of: cursor, matching: find.byType(FadeTransition)),
      );
      expect(fade.opacity.value, 1);
    });

    testWidgets('the cursor stops when the stream fails', (tester) async {
      final c = StructuredStreamController()..add('{"title": "Pan');
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      expect(cursor, findsOneWidget);
      c.close();
      await tester.pump();
      expect(c.error, isNotNull);
      expect(shown(tester), ['Pan']);
      expect(cursor, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('numbers and bools show as text; maps show nothing', (
      tester,
    ) async {
      const v = StructuredValue({
        'n': 12.5,
        'b': false,
        'm': {'a': 1},
      });
      await pumpPlain(
        tester,
        Column(
          children: [
            StructuredText(v['n']),
            StructuredText(v['b']),
            StructuredText(v['m']),
            StructuredText(v['missing']),
          ],
        ),
      );
      expect(shown(tester), ['12.5', 'false']);
    });

    testWidgets('uses the text style it is given', (tester) async {
      const style = TextStyle(fontSize: 31, color: Color(0xFF112233));
      await pumpPlain(
        tester,
        const StructuredText(StructuredValue('hi'), textStyle: style),
      );
      final rich = tester.widget<RichText>(find.byType(RichText));
      expect(rich.text.style?.fontSize, 31);
      expect(rich.text.style?.color, const Color(0xFF112233));
    });

    testWidgets('the cursor is not in the semantics tree', (tester) async {
      final handle = tester.ensureSemantics();
      final c = StructuredStreamController()..add('{"title": "Pan');
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      expect(cursor, findsOneWidget);
      expect(find.bySemanticsLabel('Pan'), findsOneWidget);
      expect(tester.getSemantics(find.byType(StructuredText)).label, 'Pan');
      // the cursor's own subtree is cut out, whatever it draws
      final exclude = tester.widget<ExcludeSemantics>(
        find.descendant(of: cursor, matching: find.byType(ExcludeSemantics)),
      );
      expect(exclude.excluding, isTrue);
      handle.dispose();
    });

    testWidgets('markdown: bold text renders once the field is closed', (
      tester,
    ) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c, markdown: true));
      expect(find.byType(StreamingMarkdown), findsOneWidget);

      await feed(tester, c, '{"title": "Fry until **cris');
      await tester.pump(const Duration(milliseconds: 500));
      var markdown = tester.widget<StreamingMarkdown>(
        find.byType(StreamingMarkdown),
      );
      expect(markdown.text, 'Fry until **cris');
      expect(markdown.isComplete, isFalse);

      await feed(tester, c, 'py** and serve"}');
      markdown = tester.widget<StreamingMarkdown>(
        find.byType(StreamingMarkdown),
      );
      expect(markdown.text, 'Fry until **crispy** and serve');
      expect(markdown.isComplete, isTrue);

      await tester.pumpAndSettle();
      expect(isBold(tester, 'crispy'), isTrue);
      expect(isBold(tester, 'Fry until'), isFalse);
      expect(shown(tester).join(), isNot(contains('**')));
      expect(shown(tester).join(), contains('and serve'));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('plain mode leaves Markdown marks alone', (tester) async {
      await pumpPlain(
        tester,
        const StructuredText(StructuredValue('a **b** c')),
      );
      expect(shown(tester), ['a **b** c']);
      expect(find.byType(StreamingMarkdown), findsNothing);
    });
  });
}
