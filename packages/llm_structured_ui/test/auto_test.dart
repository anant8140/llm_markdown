import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

import 'helpers.dart';

void main() {
  group('StructuredAuto', () {
    Widget tree(StructuredStreamController c) => StructuredBuilder(
      controller: c,
      builder: (context, data) => StructuredAuto(data),
    );

    testWidgets('a recipe, chunk by chunk', (tester) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      // nothing yet: one placeholder line
      expect(shown(tester), isEmpty);
      expect(placeholder, findsOneWidget);

      await feed(tester, c, '{');
      expect(placeholder, findsOneWidget);

      await feed(tester, c, '"title": "Pan');
      expect(shown(tester), ['title', 'Pan']);
      expect(find.byType(StructuredFields), findsOneWidget);
      expect(placeholder, findsNothing);
      expect(cursor, findsOneWidget);

      await feed(tester, c, 'cakes", "servings": 4, "steps": [');
      // the list is open and empty: its key shows with a placeholder
      expect(shown(tester), ['title', 'Pancakes', 'servings', '4', 'steps']);
      expect(placeholder, findsOneWidget);
      expect(find.byType(StructuredCard), findsNothing);

      await feed(tester, c, '{"text": "Mix", "minutes": 2}, {"text": "Fr');
      expect(shown(tester), [
        'title',
        'Pancakes',
        'servings',
        '4',
        'steps',
        'text',
        'Mix',
        'minutes',
        '2',
        'text',
        'Fr',
      ]);
      expect(find.byType(StructuredCard), findsNWidgets(2));
      expect(placeholder, findsNothing);
      expect(cursor, findsOneWidget);

      await feed(tester, c, 'y"}], "tags": ["quick", "sweet"]}');
      expect(shown(tester), [
        'title',
        'Pancakes',
        'servings',
        '4',
        'steps',
        'text',
        'Mix',
        'minutes',
        '2',
        'text',
        'Fry',
        'tags',
        'quick',
        'sweet',
      ]);
      expect(cursor, findsNothing);
      expect(placeholder, findsNothing);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('nested values are moved in under their key', (tester) async {
      await pumpPlain(
        tester,
        const StructuredAuto(
          StructuredValue({
            'name': 'Soup',
            'author': {'first': 'Ann'},
          }),
        ),
      );
      final outer = tester.getTopLeft(find.text('author'));
      final inner = tester.getTopLeft(find.text('first'));
      expect(inner.dx - outer.dx, 16);
      expect(inner.dy, greaterThan(outer.dy));
      expect(tester.getTopLeft(find.text('name')).dx, outer.dx);
    });

    testWidgets('scalars: a string is text, numbers and bools are chips', (
      tester,
    ) async {
      Future<int> chips(Object? json) async {
        await pumpPlain(tester, StructuredAuto(StructuredValue(json)));
        return find
            .descendant(
              of: find.byType(StructuredAuto),
              matching: find.byType(DecoratedBox),
            )
            .evaluate()
            .length;
      }

      expect(await chips('hello'), 0);
      expect(shown(tester), ['hello']);
      expect(find.byType(StructuredText), findsOneWidget);

      expect(await chips(42), 1);
      expect(shown(tester), ['42']);

      expect(await chips(true), 1);
      expect(shown(tester), ['true']);

      expect(await chips(null), 1);
      expect(shown(tester), ['null']);

      expect(await chips([1, 2.5, false]), 3);
      expect(shown(tester), ['1', '2.5', 'false']);
      expect(find.byType(Wrap), findsOneWidget);

      expect(await chips(['a', 1]), 1);
      expect(shown(tester), ['a', '1']);
      expect(find.byType(StructuredList), findsOneWidget);
    });

    testWidgets('a flat object is a StructuredFields with labels', (
      tester,
    ) async {
      await pumpPlain(
        tester,
        const StructuredAuto(
          StructuredValue({'a': 1, 'b': 'two'}),
          labels: {'a': 'First'},
        ),
      );
      expect(find.byType(StructuredFields), findsOneWidget);
      expect(shown(tester), ['First', '1', 'b', 'two']);
    });

    testWidgets('labels reach nested keys and cards', (tester) async {
      await pumpPlain(
        tester,
        const StructuredAuto(
          StructuredValue({
            'items': [
              {'n': 1},
            ],
            'meta': {'n': 2},
          }),
          labels: {'n': 'Count', 'items': 'Things'},
        ),
      );
      expect(shown(tester), ['Things', 'Count', '1', 'meta', 'Count', '2']);
    });

    testWidgets('the item being written is faded', (tester) async {
      final c = StructuredStreamController()..add('[{"a": "x"}, {"a": "y');
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      final opacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      expect(opacities, [1, 0.5]);
    });

    testWidgets('empty and missing values that are finished show nothing', (
      tester,
    ) async {
      for (final value in const [
        StructuredValue(<String, Object?>{}),
        StructuredValue(<Object?>[]),
        StructuredValue.missing(),
      ]) {
        await pumpPlain(tester, StructuredAuto(value));
        expect(shown(tester), isEmpty);
        expect(placeholder, findsNothing);
      }
    });

    testWidgets('nested keys are labelled for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPlain(
        tester,
        const StructuredAuto(
          StructuredValue({
            'author': {'first': 'Ann'},
          }),
        ),
      );
      expect(find.bySemanticsLabel('author'), findsOneWidget);
      expect(find.bySemanticsLabel('first\nAnn'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('after an error the last good value stays, without '
        'placeholders or cursors', (tester) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      await feed(tester, c, '{"title": "Soup", "steps": [');
      expect(placeholder, findsOneWidget);
      await feed(tester, c, '}');
      expect(c.error, isNotNull);
      expect(shown(tester), ['title', 'Soup', 'steps']);
      expect(placeholder, findsNothing);
      expect(cursor, findsNothing);
      await tester.pumpAndSettle();
    });
  });
}
