import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/code_block.dart';
import 'package:llm_markdown/src/mermaid/mermaid_model.dart';

Widget _host(Widget child, {double width = 800}) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);

const _wide =
    'flowchart LR\n  A --> B --> C --> D --> E --> F --> G --> H --> I\n';

const _flow =
    'graph TD\n  A[Start] --> B{Ready?}\n  B -->|yes| C(Go)\n  B -->|no| A\n';

void main() {
  group('drawing', () {
    testWidgets('a mermaid block is code while it streams, then a diagram', (
      tester,
    ) async {
      final controller = StreamingMarkdownController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StreamingMarkdown(
            controller: controller,
            smoothing: const Smoothing.none(),
          ),
        ),
      );
      controller.append('```mermaid\n$_flow');
      await tester.pump();
      expect(find.byType(MermaidDiagram), findsNothing);
      expect(find.byType(CodeBlockView), findsOneWidget);

      controller.append('```\n\nDone.');
      await tester.pump();
      expect(find.byType(MermaidDiagram), findsOneWidget);
      expect(find.byType(CodeBlockView), findsNothing);
      expect(
        find.bySemanticsLabel('Flowchart: Start, Ready?, Go'),
        findsOneWidget,
      );

      await tester.tap(find.text('Show code'));
      await tester.pump();
      expect(find.byType(CodeBlockView), findsOneWidget);
      expect(find.byType(MermaidDiagram), findsNothing);
      await tester.tap(find.text('Show diagram'));
      await tester.pump();
      expect(find.byType(MermaidDiagram), findsOneWidget);
    });

    testWidgets('other kinds, and diagrams: false, stay code', (tester) async {
      await tester.pumpWidget(
        _host(
          const StreamingMarkdown.text(
            '```mermaid\ngantt\n  title Plan\n```\n',
          ),
        ),
      );
      expect(find.byType(MermaidDiagram), findsNothing);
      expect(find.byType(CodeBlockView), findsOneWidget);

      await tester.pumpWidget(
        _host(
          const StreamingMarkdown.text(
            '```mermaid\n$_flow```\n',
            diagrams: false,
          ),
        ),
      );
      expect(find.byType(MermaidDiagram), findsNothing);
      expect(find.byType(CodeBlockView), findsOneWidget);
    });

    testWidgets('every kind paints; a wide one shrinks, then scrolls', (
      tester,
    ) async {
      const sources = [
        _flow,
        'flowchart LR\n  A --> B --> C --> D --> E --> F --> G --> H --> I\n'
            '  I -.-> A\n  C == big ==> F\n',
        'sequenceDiagram\n  Alice->>Bob: Hi\n  Bob-->>Alice: Hello\n'
            '  Bob->>Bob: think\n  Note over Alice,Bob: a note\n'
            '  loop again\n  Alice-xBob: bye\n  end\n',
        'pie title Pets\n"Dogs" : 3\n"Cats" : 1\n',
        'pie\n"Only" : 1\n',
      ];
      for (final source in sources) {
        await tester.pumpWidget(
          _host(MermaidDiagram(source, key: ValueKey(source)), width: 300),
        );
        expect(tester.takeException(), isNull, reason: source);
        final size = tester.getSize(find.byType(MermaidDiagram));
        expect(size.width, inInclusiveRange(40, 300), reason: source);
        expect(size.height, greaterThan(20), reason: source);
      }
      // a nine-node row is far wider than 300: it shrinks to 60% and
      // scrolls sideways for the rest
      Size painted() => tester.getSize(
        // the scroll view adds its own CustomPaint; the drawing is innermost
        find
            .descendant(
              of: find.byType(MermaidDiagram),
              matching: find.byType(CustomPaint),
            )
            .last,
      );
      await tester.pumpWidget(_host(const MermaidDiagram(_wide), width: 2000));
      final full = painted();
      await tester.pumpWidget(_host(const MermaidDiagram(_wide), width: 300));
      expect(painted().width, moreOrLessEquals(full.width * 0.6));
      expect(painted().width, greaterThan(300));
      expect(
        find.descendant(
          of: find.byType(MermaidDiagram),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      // a little too wide just shrinks
      await tester.pumpWidget(
        _host(const MermaidDiagram(_wide), width: full.width * 0.8),
      );
      expect(painted().width, moreOrLessEquals(full.width * 0.8));
    });

    testWidgets('the fallback shows for what is not drawn', (tester) async {
      await tester.pumpWidget(
        _host(const MermaidDiagram('gantt', fallback: Text('no diagram'))),
      );
      expect(find.text('no diagram'), findsOneWidget);
    });
  });

  group('reading', () {
    test('a flowchart with shapes, labels and edge kinds', () {
      final chart =
          parseMermaid('''
flowchart LR
  %% a comment
  A[Start] --> B{Is it "ok"?}
  B -->|Yes| C(Save)
  B -- No --> D([Stop]);  C -.-> E((End))
  D ==> E
  E --- F
  classDef green fill:#0f0
  class A green
''')!
              as FlowChart;
      expect(chart.direction, FlowDirection.right);
      expect(
        {for (final n in chart.nodes) n.id: (n.label, n.shape)},
        {
          'A': ('Start', NodeShape.rect),
          'B': ('Is it "ok"?', NodeShape.diamond),
          'C': ('Save', NodeShape.rounded),
          'D': ('Stop', NodeShape.stadium),
          'E': ('End', NodeShape.circle),
          'F': ('F', NodeShape.rect),
        },
      );
      expect(
        [
          for (final e in chart.edges)
            '${e.from}>${e.to} ${e.label} ${e.line.name} ${e.arrow}',
        ],
        [
          'A>B null solid true',
          'B>C Yes solid true',
          'B>D No solid true',
          'C>E null dotted true',
          'D>E null thick true',
          'E>F null solid false',
        ],
      );
    });

    test('chains, "&" groups and quoted labels with brackets', () {
      final chart =
          parseMermaid(
                'graph TD; A & B --> C --> D["a [b] c<br>next"]\n'
                'subgraph one\n  D --> A\nend\n',
              )!
              as FlowChart;
      expect(
        [for (final e in chart.edges) '${e.from}>${e.to}'],
        ['A>C', 'B>C', 'C>D', 'D>A'],
      );
      expect(chart.nodes.last.label, 'a [b] c\nnext');
    });

    test('a sequence diagram', () {
      final diagram =
          parseMermaid('''
sequenceDiagram
  participant U as User
  actor S as Server
  U->>S: Log in
  activate S
  S-->>U: Token
  Note right of S: checks the password
  loop every hour
    U-xDB: refresh
  end
''')!
              as SequenceDiagram;
      expect(diagram.participants, ['U', 'S', 'DB']);
      expect(diagram.labels, {'U': 'User', 'S': 'Server'});
      final messages = diagram.items.whereType<SequenceMessage>().toList();
      expect(
        [
          for (final m in messages)
            '${m.from}>${m.to} ${m.text} ${m.dashed} ${m.head.name}',
        ],
        [
          'U>S Log in false arrow',
          'S>U Token true arrow',
          'U>DB refresh false cross',
        ],
      );
      expect(
        diagram.items.whereType<SequenceNote>().single.side,
        NoteSide.right,
      );
      expect(
        diagram.items.whereType<SequenceDivider>().single.text,
        'loop: every hour',
      );
    });

    test('a pie chart', () {
      final pie =
          parseMermaid(
                'pie showData title Pets\n"Dogs" : 386\n"Cats" : 85.5\n',
              )!
              as PieChart;
      expect(pie.title, 'Pets');
      expect(pie.slices, [('Dogs', 386.0), ('Cats', 85.5)]);
    });

    test('other diagrams and broken input are not drawn', () {
      expect(parseMermaid('gantt\n  title Plan\n'), isNull);
      expect(parseMermaid(''), isNull);
      expect(parseMermaid('flowchart TD\n'), isNull);
      expect(parseMermaid('pie\n'), isNull);
      expect(MermaidDiagram.supports('classDiagram\n A <|-- B'), isFalse);
      expect(MermaidDiagram.supports('graph TD; A-->B'), isTrue);
    });
  });
}
