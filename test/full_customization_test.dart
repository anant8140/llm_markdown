import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:markdown/markdown.dart' as md;

const _red = Color(0xFFCC0000);
const _green = Color(0xFF00AA00);
const _blue = Color(0xFF0000CC);

final _base = StreamingMarkdownStyle.fromColors(
  textStyle: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
  accentColor: const Color(0xFF1A73E8),
);

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF2196F3),
  pageRouteBuilder: <T>(settings, builder) =>
      PageRouteBuilder<T>(pageBuilder: (context, _, _) => builder(context)),
  home: DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: Padding(
      padding: const EdgeInsets.only(top: 100),
      child: SingleChildScrollView(child: child),
    ),
  ),
);

List<TextSpan> _spans(WidgetTester tester) {
  final out = <TextSpan>[];
  void walk(InlineSpan span) {
    if (span is! TextSpan) return;
    out.add(span);
    span.children?.forEach(walk);
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(rich.text);
  }
  return out;
}

BoxDecoration _boxAround(WidgetTester tester, String text) =>
    tester
            .widget<Container>(
              find
                  .ancestor(
                    of: find.text(text),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

void main() {
  group('style', () {
    testWidgets('highlight, key caps, citations, bullets and table cells', (
      tester,
    ) async {
      const chip = BoxDecoration(color: _green);
      const cap = BoxDecoration(color: _blue);
      await tester.pumpWidget(
        _app(
          StreamingMarkdown.text(
            'An ==important== fact [7], press <kbd>Esc</kbd>.\n\n'
            '- one\n  - two\n\n'
            '| a |\n|---|\n| cell |\n',
            style: _base.copyWith(
              highlightColor: _red,
              citationDecoration: chip,
              citationTextStyle: const TextStyle(color: _red),
              kbdDecoration: cap,
              bullets: const ['→', '⇒'],
              tableCellPadding: const EdgeInsets.all(3),
            ),
          ),
        ),
      );
      expect(
        _spans(tester).where((s) => s.style?.backgroundColor == _red),
        isNotEmpty,
      );
      expect(_boxAround(tester, '7'), chip);
      expect(tester.widget<Text>(find.text('7')).style?.color, _red);
      expect(_boxAround(tester, 'Esc'), cap);
      expect(find.text('→'), findsOneWidget);
      expect(find.text('⇒'), findsOneWidget);
      expect(find.text('•'), findsNothing);
      expect(
        tester
            .widget<Padding>(
              find
                  .ancestor(
                    of: find.text('cell'),
                    matching: find.byType(Padding),
                  )
                  .first,
            )
            .padding,
        const EdgeInsets.all(3),
      );
    });

    testWidgets('spoiler cover and the thinking title', (tester) async {
      await tester.pumpWidget(
        _app(
          StreamingMarkdown.text(
            '<think>plan</think>The ||ending|| here.',
            style: _base.copyWith(
              spoilerColor: _green,
              thinkingStyle: const TextStyle(color: _red, fontSize: 11),
            ),
          ),
        ),
      );
      final cover = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text('ending'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((cover.decoration! as BoxDecoration).color, _green);
      final title = tester.widget<Text>(find.text('Thoughts'));
      expect((title.style?.color, title.style?.fontSize), (_red, 11));
    });

    testWidgets('diagram colors', (tester) async {
      Future<void> draw(String source, MarkdownDiagramStyle look) =>
          tester.pumpWidget(
            _app(
              MermaidDiagram(
                source,
                key: ValueKey(source),
                style: _base.copyWith(diagramStyle: look),
              ),
            ),
          );
      Finder drawing() => find
          .descendant(
            of: find.byType(MermaidDiagram),
            matching: find.byType(CustomPaint),
          )
          .last;

      await draw(
        'graph TD; A --> B',
        const MarkdownDiagramStyle(lineColor: _red, nodeColor: _green),
      );
      expect(
        drawing(),
        paints
          ..path(color: _red) // the edge
          ..path(color: _red) // its arrow head
          ..path(color: _green), // a node
      );

      await draw(
        'pie\n"x" : 1\n"y" : 2\n',
        const MarkdownDiagramStyle(pieColors: [_blue, _red]),
      );
      expect(
        drawing(),
        paints
          ..arc(color: _blue)
          ..arc(color: _red),
      );
    });

    test('new parts count in ==, copyWith and lerp', () {
      // each new part on its own makes a different style
      final changed = [
        _base.copyWith(highlightColor: _red),
        _base.copyWith(spoilerColor: _red),
        _base.copyWith(citationDecoration: const BoxDecoration(color: _red)),
        _base.copyWith(citationTextStyle: const TextStyle(color: _red)),
        _base.copyWith(kbdDecoration: const BoxDecoration(color: _red)),
        _base.copyWith(thinkingStyle: const TextStyle(color: _red)),
        _base.copyWith(imageBarrierColor: _red),
        _base.copyWith(bullets: const ['*']),
        _base.copyWith(tableCellPadding: EdgeInsets.zero),
        _base.copyWith(
          diagramStyle: const MarkdownDiagramStyle(pieColors: [_red]),
        ),
      ];
      for (var i = 0; i < changed.length; i++) {
        expect(changed[i], isNot(_base), reason: 'part $i');
      }
      expect(
        const MarkdownLabels(showCode: 'x'),
        isNot(const MarkdownLabels()),
      );
      expect(
        const MarkdownLabels(alertTitles: {'tip': 'T'}),
        const MarkdownLabels(alertTitles: {'tip': 'T'}),
      );
      final styled = _base.copyWith(
        highlightColor: _red,
        diagramStyle: const MarkdownDiagramStyle(nodeColor: _green),
      );
      expect(styled, isNot(_base));
      expect(
        styled,
        _base.copyWith(
          highlightColor: _red,
          diagramStyle: const MarkdownDiagramStyle(nodeColor: _green),
        ),
      );
      expect(styled.hashCode, isNot(_base.hashCode));
      final other = _base.copyWith(highlightColor: _blue);
      expect(
        StreamingMarkdownStyle.lerp(styled, other, 0.5).highlightColor,
        Color.lerp(_red, _blue, 0.5),
      );
      expect(
        const MarkdownDiagramStyle().copyWith(lineColor: _red).lineColor,
        _red,
      );
    });
  });

  group('labels', () {
    const labels = MarkdownLabels(
      copy: 'KOPIEREN',
      showCode: 'CODE',
      showDiagram: 'BILD',
      showLess: 'WENIGER',
      details: 'MEHR',
      alertTitles: {'tip': 'TIPP'},
    );
    const reply =
        '> [!TIP]\n> Use it.\n\n> [!NOTE]\n> Read it.\n\n'
        '<details>\nhidden\n</details>\n\n'
        '```mermaid\ngraph TD; A-->B\n```\n\n'
        '```dart\na;\nb;\nc;\n```\n';

    testWidgets('replace the built-in text', (tester) async {
      await tester.pumpWidget(
        _app(
          StreamingMarkdown.text(
            reply,
            labels: MarkdownLabels(
              copy: labels.copy,
              showCode: labels.showCode,
              showDiagram: labels.showDiagram,
              showLess: labels.showLess,
              details: labels.details,
              alertTitles: labels.alertTitles,
              showAllLines: (lines) => 'ALLE $lines',
            ),
            codeBlocks: const CodeBlockOptions(collapseAfterLines: 2),
          ),
        ),
      );
      expect(find.text('TIPP'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget); // not translated: English
      expect(find.text('MEHR'), findsOneWidget);
      expect(find.text('KOPIEREN'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);

      await tester.tap(find.text('ALLE 3'));
      await tester.pump();
      expect(find.text('WENIGER'), findsOneWidget);

      await tester.ensureVisible(find.text('CODE'));
      await tester.tap(find.text('CODE'));
      await tester.pump();
      expect(find.text('BILD'), findsOneWidget);
    });

    testWidgets('come from the theme too, and a widget\'s own win', (
      tester,
    ) async {
      Widget themed({MarkdownLabels? own}) => _app(
        StreamingMarkdownTheme(
          style: _base,
          labels: labels,
          child: StreamingMarkdown.text('> [!TIP]\n> x\n', labels: own),
        ),
      );
      await tester.pumpWidget(themed());
      expect(find.text('TIPP'), findsOneWidget);
      await tester.pumpWidget(
        themed(own: const MarkdownLabels(alertTitles: {'tip': 'ASTUCE'})),
      );
      expect(find.text('ASTUCE'), findsOneWidget);
    });
  });

  group('builders', () {
    testWidgets('thinking section and cursor', (tester) async {
      final seen = <(bool, String)>[];
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
            thinkingBuilder: (context, thinking) {
              seen.add((thinking.done, thinking.label));
              return Column(
                children: [const Text('MY THINKING'), thinking.content],
              );
            },
            cursorBuilder: (context, textStyle) =>
                Text('▌', style: textStyle.copyWith(color: _red)),
          ),
        ),
      );
      controller.append('<think>a plan');
      await tester.pump();
      expect(find.text('MY THINKING'), findsOneWidget);
      expect(seen.last, (false, 'Thinking'));
      // the thoughts are visible: the built-in section would be closed
      expect(find.textContaining('a plan'), findsOneWidget);

      controller.append('</think>An answer');
      await tester.pump();
      expect(seen.last.$1, isTrue);
      expect(find.text('▌'), findsOneWidget);

      controller.complete();
      await tester.pump();
      expect(find.text('▌'), findsNothing);
    });

    testWidgets('list items', (tester) async {
      await tester.pumpWidget(
        _app(
          StreamingMarkdown.text(
            '- alpha\n- beta\n',
            elementBuilders: {
              'li': (BuildContext context, md.Element item, bool complete) =>
                  Text('ITEM ${item.textContent}'),
            },
          ),
        ),
      );
      expect(find.text('ITEM alpha'), findsOneWidget);
      expect(find.text('ITEM beta'), findsOneWidget);
      expect(find.text('•'), findsNothing);
    });
  });

  group('selection menu', () {
    Future<void> select(WidgetTester tester) async {
      await tester.longPressAt(
        tester.getTopLeft(find.byType(RichText)) + const Offset(30, 8),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('colors', (tester) async {
      await tester.pumpWidget(
        _app(
          const MarkdownSelectionArea(
            menuColor: _green,
            menuTextStyle: TextStyle(color: _red, fontSize: 20),
            menuBorderRadius: BorderRadius.zero,
            child: StreamingMarkdown.text('Streaming markdown rocks.'),
          ),
        ),
      );
      await select(tester);
      final label = tester.widget<Text>(find.text('Copy'));
      expect((label.style?.color, label.style?.fontSize), (_red, 20));
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('Copy'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(
        (decoration.color, decoration.borderRadius),
        (_green, BorderRadius.zero),
      );
    });

    testWidgets('a menu of your own', (tester) async {
      String? asked;
      await tester.pumpWidget(
        _app(
          MarkdownSelectionArea(
            actions: [
              MarkdownSelectionAction(
                label: 'Ask',
                onSelected: (text) => asked = text,
              ),
            ],
            menuBuilder: (context, items, anchors) => Align(
              alignment: Alignment.topLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    GestureDetector(
                      onTap: item.onPressed,
                      child: Text('<${item.label}>'),
                    ),
                ],
              ),
            ),
            child: const StreamingMarkdown.text('Streaming markdown rocks.'),
          ),
        ),
      );
      await select(tester);
      expect(find.text('<Copy>'), findsOneWidget);
      expect(find.text('<Select all>'), findsOneWidget);
      await tester.tap(find.text('<Ask>'));
      await tester.pumpAndSettle();
      expect(asked, 'Streaming');
    });
  });
}
