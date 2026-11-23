import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

import 'helpers.dart';

void main() {
  group('StructuredCard', () {
    testWidgets('parts by key fill in as they arrive', (tester) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        StructuredBuilder(
          controller: c,
          builder: (context, data) => StructuredCard(
            data,
            title: 'name',
            subtitle: 'cuisine',
            body: 'summary',
            footer: 'source',
          ),
        ),
      );
      // nothing yet: every part waits
      expect(shown(tester), isEmpty);
      expect(placeholder, findsNWidgets(4));

      await feed(tester, c, '{"name": "Pan');
      expect(shown(tester), ['Pan']);
      expect(cursor, findsOneWidget);
      expect(placeholder, findsNWidgets(3));

      await feed(tester, c, 'cakes", "cuisine": "French", "summary": "Thin');
      expect(shown(tester), ['Pancakes', 'French', 'Thin']);
      expect(placeholder, findsOneWidget);

      // the footer never comes: its placeholder goes when the object ends
      await feed(tester, c, ' and quick."}');
      expect(shown(tester), ['Pancakes', 'French', 'Thin and quick.']);
      expect(placeholder, findsNothing);
      expect(cursor, findsNothing);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a finished empty part has no placeholder', (tester) async {
      final c = StructuredStreamController()..add('{"name": "", "by": "');
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        StructuredBuilder(
          controller: c,
          builder: (context, data) =>
              StructuredCard(data, title: 'name', subtitle: 'by'),
        ),
      );
      // only the subtitle, which is still being written, waits
      expect(placeholder, findsOneWidget);
      await feed(tester, c, '"}');
      expect(placeholder, findsNothing);
    });

    testWidgets('title and subtitle use their styles', (tester) async {
      await pumpPlain(
        tester,
        const StructuredCard(
          StructuredValue({'name': 'Soup', 'by': 'Ann', 'text': 'Hot'}),
          title: 'name',
          subtitle: 'by',
          body: 'text',
        ),
        textStyle: const TextStyle(fontSize: 10, color: Color(0xFF000000)),
      );
      TextStyle styleOf(String text) => tester
          .widget<RichText>(find.text(text, findRichText: true))
          .text
          .style!;
      expect(styleOf('Soup').fontSize, 12);
      expect(styleOf('Soup').fontWeight, FontWeight.w600);
      expect(styleOf('Ann').fontSize, 10);
      expect(styleOf('Ann').color!.a, closeTo(0.62, 0.01));
      expect(styleOf('Hot').color, const Color(0xFF000000));
    });

    testWidgets('without a body the other keys are shown as fields', (
      tester,
    ) async {
      await pumpPlain(
        tester,
        const StructuredCard(
          StructuredValue({
            'name': 'Soup',
            'by': 'Ann',
            'minutes': 20,
            'vegan': true,
          }),
          title: 'name',
          footer: 'by',
        ),
      );
      expect(find.byType(StructuredFields), findsOneWidget);
      expect(shown(tester), ['Soup', 'minutes', '20', 'vegan', 'true', 'Ann']);
    });

    testWidgets('no fields body when every key is used', (tester) async {
      await pumpPlain(
        tester,
        const StructuredCard(StructuredValue({'name': 'Soup'}), title: 'name'),
      );
      expect(find.byType(StructuredFields), findsNothing);
      expect(shown(tester), ['Soup']);
    });

    testWidgets('builders replace keys', (tester) async {
      await pumpPlain(
        tester,
        StructuredCard(
          const StructuredValue({'name': 'Soup', 'minutes': 20}),
          title: 'name',
          titleBuilder: (context, v) => Text('T:${v['name'].asString}'),
          subtitleBuilder: (context, v) => Text('S:${v['minutes'].asNum}'),
          bodyBuilder: (context, v) => const Text('B'),
          footerBuilder: (context, v) => const Text('F'),
        ),
      );
      expect(shown(tester), ['T:Soup', 'S:20', 'B', 'F']);
    });

    testWidgets('bodyMarkdown draws the body as Markdown', (tester) async {
      await pumpPlain(
        tester,
        const StructuredCard(
          StructuredValue({'name': 'Soup', 'text': 'Very **hot**'}),
          title: 'name',
          body: 'text',
          bodyMarkdown: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StreamingMarkdown), findsOneWidget);
      expect(shown(tester).join('|'), isNot(contains('**')));
      expect(shown(tester).first, 'Soup');
    });

    testWidgets('fills the width it is given, and survives none', (
      tester,
    ) async {
      const card = StructuredCard(
        StructuredValue({'name': 'Soup'}),
        title: 'name',
      );
      await pumpPlain(tester, const SizedBox(width: 300, child: card));
      expect(tester.getSize(find.byType(StructuredCard)).width, 300);

      await pumpPlain(tester, const Row(children: [card]));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StructuredCard)).width, lessThan(200));
    });

    testWidgets('has a border and background from the style', (tester) async {
      late StructuredStyle style;
      await pumpPlain(
        tester,
        Builder(
          builder: (context) {
            style = StructuredStyle.of(context).copyWith(
              cardColor: const Color(0xFF010203),
              cardBorderColor: const Color(0xFF040506),
              cardRadius: 7,
            );
            return StructuredCard(
              const StructuredValue({'name': 'Soup'}),
              title: 'name',
              style: style,
            );
          },
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(StructuredCard),
          matching: find.byType(DecoratedBox),
        ),
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF010203));
      expect((decoration.border! as Border).top.color, const Color(0xFF040506));
      expect(decoration.borderRadius, BorderRadius.circular(7));
    });

    testWidgets('semantics: a labelled container with a header title', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPlain(
        tester,
        const StructuredCard(
          StructuredValue({'name': 'Soup', 'text': 'Hot'}),
          title: 'name',
          body: 'text',
          semanticLabel: 'Recipe',
        ),
      );
      expect(find.bySemanticsLabel('Recipe'), findsOneWidget);
      final title = tester.getSemantics(find.bySemanticsLabel('Soup'));
      expect(title.flagsCollection.isHeader, isTrue);
      final body = tester.getSemantics(find.bySemanticsLabel('Hot'));
      expect(body.flagsCollection.isHeader, isFalse);
      handle.dispose();
    });
  });
}
