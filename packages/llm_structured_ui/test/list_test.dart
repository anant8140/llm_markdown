import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_structured_ui/llm_structured_ui.dart';

import 'helpers.dart';

void main() {
  group('StructuredList', () {
    Widget tree(
      StructuredStreamController c, {
      bool showPendingItem = true,
      StructuredStyle? style,
    }) => StructuredBuilder(
      controller: c,
      builder: (context, data) => StructuredList(
        data['steps'],
        showPendingItem: showPendingItem,
        style: style,
        itemBuilder: (context, item, index) =>
            Text('${index + 1}. ${item.asString ?? ''}'),
      ),
    );

    double opacityOf(WidgetTester tester, String text) => tester
        .widget<Opacity>(
          find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
        )
        .opacity;

    testWidgets('items appear as they arrive; the pending one is faded', (
      tester,
    ) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c));
      expect(shown(tester), isEmpty);

      await feed(tester, c, '{"steps": [');
      expect(shown(tester), isEmpty);

      await feed(tester, c, '"Mix", "Fr');
      expect(shown(tester), ['1. Mix', '2. Fr']);
      expect(opacityOf(tester, '1. Mix'), 1);
      expect(opacityOf(tester, '2. Fr'), 0.5);

      await feed(tester, c, 'y", "Serve"');
      expect(shown(tester), ['1. Mix', '2. Fry', '3. Serve']);
      expect(opacityOf(tester, '2. Fry'), 1);
      expect(opacityOf(tester, '3. Serve'), 1);

      await feed(tester, c, ']}');
      expect(shown(tester), ['1. Mix', '2. Fry', '3. Serve']);
      await tester.pumpAndSettle();
    });

    testWidgets('pendingOpacity comes from the style', (tester) async {
      final c = StructuredStreamController()..add('{"steps": ["Mix", "Fr');
      addTearDown(c.dispose);
      late StructuredStyle base;
      await pumpPlain(
        tester,
        Builder(
          builder: (context) {
            base = StructuredStyle.of(context);
            return tree(c, style: base.copyWith(pendingOpacity: 0.25));
          },
        ),
      );
      expect(opacityOf(tester, '2. Fr'), 0.25);
      expect(opacityOf(tester, '1. Mix'), 1);
    });

    testWidgets('showPendingItem false hides an item until it is done', (
      tester,
    ) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      await pumpPlain(tester, tree(c, showPendingItem: false));

      await feed(tester, c, '{"steps": ["Mix", "Fr');
      expect(shown(tester), ['1. Mix']);

      await feed(tester, c, 'y"');
      expect(shown(tester), ['1. Mix', '2. Fry']);

      await feed(tester, c, ', "Ser');
      expect(shown(tester), ['1. Mix', '2. Fry']);

      await feed(tester, c, 've"]}');
      expect(shown(tester), ['1. Mix', '2. Fry', '3. Serve']);
    });

    testWidgets('an item keeps its state when it finishes', (tester) async {
      final c = StructuredStreamController();
      addTearDown(c.dispose);
      var inits = 0;
      await pumpPlain(
        tester,
        StructuredBuilder(
          controller: c,
          builder: (context, data) => StructuredList(
            data,
            itemBuilder: (context, item, index) =>
                _Counted(onInit: () => inits++),
          ),
        ),
      );
      await feed(tester, c, '["a');
      expect(inits, 1);
      await feed(tester, c, '", "b"]');
      expect(inits, 2);
    });

    testWidgets('something that is not a list shows nothing', (tester) async {
      await pumpPlain(
        tester,
        StructuredList(
          const StructuredValue({'a': 1}),
          itemBuilder: (context, item, index) => const Text('item'),
        ),
      );
      expect(shown(tester), isEmpty);
    });

    testWidgets('semanticLabel labels the list', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPlain(
        tester,
        StructuredList(
          const StructuredValue(['a', 'b']),
          semanticLabel: 'Steps',
          itemBuilder: (context, item, index) => Text(item.asString!),
        ),
      );
      expect(find.bySemanticsLabel('Steps'), findsOneWidget);
      expect(find.bySemanticsLabel('a'), findsOneWidget);
      handle.dispose();
    });
  });
}

class _Counted extends StatefulWidget {
  const _Counted({required this.onInit});
  final VoidCallback onInit;
  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
