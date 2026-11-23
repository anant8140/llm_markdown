import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

import 'helpers.dart';

void main() {
  group('StructuredFields', () {
    Widget tree(
      StructuredStreamController c, {
      Map<String, String> labels = const {},
      List<String> order = const [],
      Set<String> hide = const {},
    }) => StructuredBuilder(
      controller: c,
      builder: (context, data) =>
          StructuredFields(data, labels: labels, order: order, hide: hide),
    );

    testWidgets('rows fill in as values arrive', (tester) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      expect(shown(tester), isEmpty);
      expect(placeholder, findsNothing);

      // a key shows once its value has started; an empty string so far
      // has a placeholder line
      await feed(tester, c, '{"name": "');
      expect(shown(tester), ['name']);
      expect(placeholder, findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);

      await feed(tester, c, 'Pan');
      expect(shown(tester), ['name', 'Pan']);
      expect(placeholder, findsNothing);
      expect(cursor, findsOneWidget);

      await feed(tester, c, 'cakes", "servings": 4');
      expect(shown(tester), ['name', 'Pancakes', 'servings', '4']);
      expect(cursor, findsOneWidget);

      await feed(tester, c, ', "vegan": false, "note": null}');
      expect(shown(tester), [
        'name',
        'Pancakes',
        'servings',
        '4',
        'vegan',
        'false',
        'note',
        '–',
      ]);
      expect(cursor, findsNothing);
      expect(placeholder, findsNothing);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('order gives rows a placeholder before they arrive', (
      tester,
    ) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        tree(
          c,
          order: const ['servings', 'name'],
          labels: const {'servings': 'Serves', 'name': 'Dish'},
        ),
      );
      // before anything arrives both rows wait
      expect(shown(tester), ['Serves', 'Dish']);
      expect(placeholder, findsNWidgets(2));

      await feed(tester, c, '{"name": "Soup", "extra": 1, ');
      expect(shown(tester), ['Serves', 'Dish', 'Soup', 'extra', '1']);
      expect(placeholder, findsOneWidget);

      await feed(tester, c, '"servings": 2}');
      expect(shown(tester), ['Serves', '2', 'Dish', 'Soup', 'extra', '1']);
      expect(placeholder, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('a key in order that never arrives has no row at the end', (
      tester,
    ) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c, order: const ['name', 'servings']));
      await feed(tester, c, '{"name": "Soup"');
      expect(shown(tester), ['name', 'Soup', 'servings']);
      expect(placeholder, findsOneWidget);
      await feed(tester, c, '}');
      expect(shown(tester), ['name', 'Soup']);
      expect(placeholder, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('placeholders go away when the stream fails', (tester) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c, order: const ['name', 'servings']));
      await feed(tester, c, '{"name": "Soup", ');
      expect(placeholder, findsOneWidget);
      await feed(tester, c, '??');
      expect(c.error, isNotNull);
      expect(shown(tester), ['name', 'Soup']);
      expect(placeholder, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('a finished empty string is an empty row, not a '
        'placeholder', (tester) async {
      final c = StructuredStreamController()..add('{"note": "", "n": 1');
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      expect(shown(tester), ['note', 'n', '1']);
      expect(placeholder, findsNothing);
    });

    testWidgets('hide leaves keys out', (tester) async {
      final c = StructuredStreamController()
        ..add('{"id": 7, "name": "Soup", "secret": "x"}');
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        tree(c, hide: const {'id', 'secret'}, order: const ['secret', 'name']),
      );
      expect(shown(tester), ['name', 'Soup']);
    });

    testWidgets('the placeholder pulses, and stands still when animations '
        'are disabled', (tester) async {
      final c = StructuredStreamController()..add('{"name": "');
      addTearDown(c.dispose);
      double opacity() => tester
          .widget<FadeTransition>(
            find.descendant(
              of: placeholder,
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;

      await pumpPlain(tester, tree(c));
      final seen = <double>{};
      for (var i = 0; i < 10; i++) {
        seen.add(opacity());
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(seen.length, greaterThan(3));
      expect(seen.every((o) => o >= 0.4 && o <= 1), isTrue);

      await pumpPlain(tester, tree(c), disableAnimations: true);
      await tester.pump();
      expect(placeholder, findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      expect(opacity(), 1);
      await tester.pumpAndSettle();

      // and starts again when they are allowed again
      await pumpPlain(tester, tree(c));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('rows are read as label and value; placeholders are '
        'left out', (tester) async {
      final handle = tester.ensureSemantics();
      final c = StructuredStreamController()..add('{"name": "Soup", ');
      addTearDown(c.dispose);
      await pumpPlain(
        tester,
        tree(
          c,
          order: const ['name', 'servings'],
          labels: const {'name': 'Dish', 'servings': 'Serves'},
        ),
      );
      expect(find.bySemanticsLabel('Dish\nSoup'), findsOneWidget);
      // the label is read once, with its value
      expect(find.bySemanticsLabel('Dish'), findsNothing);
      // the waiting row has its label and nothing for the placeholder
      expect(find.bySemanticsLabel('Serves'), findsOneWidget);
      expect(placeholder, findsOneWidget);
      final exclude = tester.widget<ExcludeSemantics>(
        find.descendant(
          of: placeholder,
          matching: find.byType(ExcludeSemantics),
        ),
      );
      expect(exclude.excluding, isTrue);
      handle.dispose();
    });

    testWidgets('valueBuilder replaces a value; null keeps the usual one', (
      tester,
    ) async {
      await pumpPlain(
        tester,
        StructuredFields(
          const StructuredValue({'minutes': 20, 'name': 'Soup'}),
          valueBuilder: (context, key, value) =>
              key == 'minutes' ? Text('${value.asNum} min') : null,
        ),
      );
      expect(shown(tester), ['minutes', '20 min', 'name', 'Soup']);
    });

    testWidgets('a nested value is drawn inside its row', (tester) async {
      await pumpPlain(
        tester,
        const StructuredFields(
          StructuredValue({
            'name': 'Soup',
            'tags': ['hot', 'quick'],
          }),
        ),
      );
      expect(shown(tester), ['name', 'Soup', 'tags', 'hot', 'quick']);
      // the list itself and its two items
      expect(find.byType(StructuredAuto), findsNWidgets(3));
    });
  });
}
