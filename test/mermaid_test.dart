import 'dart:math' as math;
import 'dart:ui' as ui;

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

const _subgraphs = '''
flowchart TD
  A[Start] --> B
  subgraph one [Back end]
    B --> C
    subgraph inner
      D
    end
  end
  subgraph "Front end"
    E
  end
  subgraph two
    F --> G
  end
  C --> two
  two --> E
''';

const _er = '''
erDiagram
  CUSTOMER ||--o{ ORDER : places
  ORDER ||--|{ LINE-ITEM : contains
  CUSTOMER }|..|| DELIVERY-ADDRESS : uses
  PRODUCT |o--o| LINE-ITEM : "is in"
  CUSTOMER {
    string name PK "full name"
    int age
  }
  ORDER["Customer order"] {
    int id PK, FK
  }
''';

const _gantt = '''
gantt
  title Release
  dateFormat YYYY-MM-DD
  section Build
  Design :done, a1, 2024-01-01, 3d
  Code :active, a2, after a1, 1w
  section Ship
  Test :crit, 2024-01-08, 2024-01-12
  Docs :2d
  Launch :milestone, m1, 2024-01-15, 0d
''';

const _mindmap = '''
mindmap
  root((Plan))
    Goals
      Speed
      ::icon(fa fa-bolt)
      id1[Cost]
    Risks
      r)Scope(
      r2{{Time}}
''';

const _timeline = '''
timeline
  title History
  section Early
    2002 : LinkedIn
    2004 : Facebook : Google
         : Flickr
  section Later
    2010 : Instagram
    2012
''';

class _Drawn {
  final nodes = <Rect>[];
  final notes = <Rect>[];
  final boxes = <Rect>[];
  final lines = <Rect>[];
  final linePaths = <Path>[];
  final fills = <Path>[];
  final texts = <ui.Paragraph>[];
  // where each paragraph's text was painted (centered text only)
  final textAreas = <Rect>[];
}

const _sideNotes = '''
stateDiagram-v2
  direction LR
  A --> B
  B --> C
  A --> C
  note right of B : hi
  note left of A : lo
''';

const _states = '''
stateDiagram-v2
  [*] --> Idle
  Idle --> Busy : start
  state Busy {
    [*] --> Run
    Run --> [*]
  }
  Busy --> Idle : done
  note right of Busy : working
  note left of Idle
    two
    lines
  end note
''';

const _classes = '''
classDiagram
  class Animal {
    <<abstract>>
    +String name
    +eat() bool
  }
  Animal <|-- Duck : is a
  Zoo "1" *-- "many" Animal : holds
  note for Zoo "a note"
''';

const _sequence = '''
sequenceDiagram
  participant A as Alice
  A->>B: Hi
  B-->>A: Hello
  Note right of B: thinks
  loop again
    A-xB: bye
  end
''';

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
        'stateDiagram-v2\n  [*] --> A\n  A --> B : go\n  B --> A : back\n'
            '  state c <<choice>>\n  B --> c\n  c --> [*]\n',
        'classDiagram\n  class Animal {\n    <<abstract>>\n    +String name\n'
            '    +eat() bool\n  }\n  Animal <|-- Duck\n  Zoo *-- Animal\n'
            '  Zoo o-- Keeper\n  Keeper ..> Animal\n  Duck --> Zoo\n',
        'pie\n"Only" : 1\n',
        _subgraphs,
        'stateDiagram-v2\n  [*] --> Busy\n  state Busy {\n    [*] --> Run\n'
            '    Run --> [*]\n  }\n  Busy --> Done\n  note right of Run : hot\n',
        'classDiagram\n  Zoo "1" *-- "many" Animal : holds\n'
            '  note for Zoo "a note"\n',
        _er,
        _gantt,
        _mindmap,
        _timeline,
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

    // what a diagram draws, from its canvas calls
    Future<_Drawn> drawn(WidgetTester tester, String source) async {
      await tester.pumpWidget(
        _host(MermaidDiagram(source, key: ValueKey(source))),
      );
      final seen = _Drawn();
      final strokes = <Rect>[];
      expect(
        tester.renderObject(
          find
              .descendant(
                of: find.byType(MermaidDiagram),
                matching: find.byType(CustomPaint),
              )
              .last,
        ),
        paints..everything((method, arguments) {
          final paint = arguments.length > 1 && arguments[1] is Paint
              ? arguments[1] as Paint
              : null;
          if (method == #drawPath && paint!.style == PaintingStyle.fill) {
            final path = arguments[0] as Path;
            final bounds = path.getBounds();
            seen.fills.add(path);
            // a note: its top right corner folded off, the bottom right
            // one square
            if (!path.contains(bounds.topRight + const Offset(-3, 3)) &&
                path.contains(bounds.bottomRight + const Offset(-1, -1))) {
              seen.notes.add(bounds);
            } else if (bounds.height > 20) {
              seen.nodes.add(bounds);
            }
          } else if (method == #drawPath) {
            strokes.add((arguments[0] as Path).getBounds());
            seen.linePaths.add(arguments[0] as Path);
          } else if (method == #drawRRect &&
              paint!.style == PaintingStyle.fill &&
              (arguments[0] as RRect).tlRadiusX == 8) {
            seen.boxes.add((arguments[0] as RRect).outerRect);
          } else if (method == #drawParagraph) {
            final paragraph = arguments[0] as ui.Paragraph;
            seen.texts.add(paragraph);
            // the text is centered in the width it was laid out in
            seen.textAreas.add(
              (arguments[1] as Offset) +
                      Offset((paragraph.width - paragraph.longestLine) / 2, 0) &
                  Size(paragraph.longestLine, paragraph.height),
            );
          }
          return true;
        }),
      );
      // the same box or node can be painted again under an erased label
      seen
        ..nodes.replaceRange(0, seen.nodes.length, seen.nodes.toSet())
        ..boxes.replaceRange(0, seen.boxes.length, seen.boxes.toSet());
      // the lines: strokes that aren't a node's or note's outline
      seen.lines.addAll(
        strokes.where(
          (rect) => !seen.nodes.contains(rect) && !seen.notes.contains(rect),
        ),
      );
      return seen;
    }

    testWidgets('edges each way between two nodes run apart', (tester) async {
      List<Offset> points(Path path) => [
        for (final metric in path.computeMetrics())
          for (var at = 0.0; at <= metric.length; at += 1)
            metric.getTangentForOffset(at)!.position,
      ];
      for (final direction in ['TD', 'LR']) {
        final chart = await drawn(
          tester,
          'flowchart $direction\n  A[Start] -->|go| B[Next]\n'
          '  B -->|back| A\n',
        );
        // the two lines, not the node outlines
        final [go, back] = [
          for (final path in chart.linePaths)
            if (!chart.nodes.contains(path.getBounds())) points(path),
        ];
        var closest = double.infinity;
        for (final a in go) {
          for (final b in back) {
            closest = math.min(closest, (a - b).distance);
          }
        }
        expect(closest, greaterThanOrEqualTo(14), reason: direction);
        // each label beside its own line: on no line
        for (final area in chart.textAreas.take(2)) {
          for (final point in [...go, ...back]) {
            expect(area.contains(point), isFalse, reason: direction);
          }
        }
      }
      // three edges from one node, two of them a pair: no two labels meet
      final chart = await drawn(
        tester,
        'stateDiagram-v2\n  [*] --> Streaming\n'
        '  Streaming --> Done : complete()\n'
        '  Streaming --> Failed : error\n'
        '  Failed --> Streaming : retry\n  Done --> [*]\n',
      );
      final labels = chart.textAreas.take(3).toList();
      for (var i = 0; i < labels.length; i++) {
        for (var j = i + 1; j < labels.length; j++) {
          expect(labels[i].overlaps(labels[j]), isFalse);
        }
      }
      // the pair's labels keep to their own sides: error (along the flow)
      // left, retry (against it) right
      final [error, retry, complete] = labels;
      expect(error.right, lessThan(retry.left));
      // and complete(), moved out of their way, stays toward Done: left
      expect(complete.right, lessThanOrEqualTo(error.left + 0.5));
    });

    testWidgets('a subgraph box holds its nodes and no others', (tester) async {
      // CDN shares a rank with Gateway, inside the span of Auth and Orders
      final chart = await drawn(
        tester,
        'flowchart TD\n  subgraph api [API]\n    G[Gateway] --> A[Auth]\n'
        '    G --> O[Orders]\n  end\n  U[User] --> G\n  U --> CDN[CDN]\n',
      );
      final nodes = chart.nodes;
      expect(nodes, hasLength(5));
      final box = chart.boxes.single;
      expect(nodes.where((n) => box.contains(n.center)), hasLength(3));
      // the rest are wholly outside
      expect(
        nodes.where((n) => !box.contains(n.center) && box.overlaps(n)),
        isEmpty,
      );
      // one rank, written A, X, B: A and B still sit together
      final row = await drawn(
        tester,
        'flowchart TD\n  subgraph s\n    A\n  end\n  X\n  subgraph s\n'
        '    B\n  end\n',
      );
      final rowBox = row.boxes.single;
      expect(row.nodes.where((n) => rowBox.contains(n.center)), hasLength(2));
      expect(
        row.nodes.where((n) => !rowBox.contains(n.center)).single,
        isNot(predicate<Rect>(rowBox.overlaps)),
      );
    });

    testWidgets('a box is as wide as its title', (tester) async {
      for (final direction in ['TD', 'LR', 'RL']) {
        final chart = await drawn(
          tester,
          'flowchart $direction\n  subgraph s [A very long title for one node]\n'
          '    A\n  end\n  B --> A\n  B --> C\n  A --> D\n',
        );
        final title = chart.texts
            .where((text) => text.longestLine > 150)
            .single;
        expect(title.didExceedMaxLines, isFalse, reason: direction);
        final box = chart.boxes.single;
        expect(box.width, greaterThan(title.longestLine), reason: direction);
        // and holds no one else
        expect(
          chart.nodes.where((n) => box.overlaps(n)),
          hasLength(1),
          reason: direction,
        );
      }
    });

    testWidgets('no line runs over a group title', (tester) async {
      await tester.pumpWidget(
        _host(
          const MermaidDiagram(
            'flowchart TD\n  subgraph d [Data kept for years]\n'
            '    P[Postgres]\n  end\n  A --> P\n  B --> P\n',
          ),
        ),
      );
      // every call, in order
      final calls = <(Symbol, List<dynamic>)>[];
      expect(
        tester.renderObject(
          find
              .descendant(
                of: find.byType(MermaidDiagram),
                matching: find.byType(CustomPaint),
              )
              .last,
        ),
        paints..everything((method, arguments) {
          calls.add((method, arguments));
          return true;
        }),
      );
      final box = calls
          .where((c) => c.$1 == #drawRRect && (c.$2[0] as RRect).tlRadiusX == 8)
          .map((c) => (c.$2[0] as RRect).outerRect)
          .first;
      // the title: the text at the box's top left
      final title = calls.indexWhere(
        (c) =>
            c.$1 == #drawParagraph &&
            ((c.$2[1] as Offset) - box.topLeft).distance < 20,
      );
      final paragraph = calls[title].$2[0] as ui.Paragraph;
      final area =
          (calls[title].$2[1] as Offset) &
          Size(paragraph.longestLine, paragraph.height);
      // an edge does run through it ...
      final crossing = [
        for (var k = 0; k < calls.length; k++)
          if (calls[k].$1 == #drawPath &&
              (calls[k].$2[1] as Paint).style == PaintingStyle.stroke &&
              (calls[k].$2[0] as Path).getBounds().overlaps(area))
            k,
      ];
      expect(crossing, isNotEmpty);
      // ... but before it is cleared, and the title is written after that
      final cleared = calls.lastIndexWhere(
        (c) =>
            c.$1 == #drawRect &&
            (c.$2[1] as Paint).blendMode == BlendMode.clear &&
            (c.$2[0] as Rect).inflate(0.5).contains(area.topLeft) &&
            (c.$2[0] as Rect).inflate(0.5).contains(area.bottomRight),
      );
      expect(cleared, greaterThan(crossing.last));
      expect(title, greaterThan(cleared));
    });

    testWidgets('a composite state is a box, not a node', (tester) async {
      final chart = await drawn(
        tester,
        'stateDiagram-v2\n  A --> Busy\n  state Busy {\n    Run --> Wait\n'
        '  }\n  Busy --> B\n',
      );
      // A, B, Run and Wait; Busy is the box around Run and Wait
      expect(chart.nodes, hasLength(4));
      expect(
        chart.nodes.where((n) => chart.boxes.single.contains(n.center)),
        hasLength(2),
      );
    });

    testWidgets('a loop back out of a composite leaves from its box', (
      tester,
    ) async {
      final chart = await drawn(
        tester,
        'stateDiagram-v2\n  A --> Busy\n  state Busy {\n    Run --> Wait\n'
        '  }\n  Busy --> A\n',
      );
      final box = chart.boxes.single;
      // every line is inside the box (Run to Wait) or wholly above it
      for (final line in chart.lines) {
        expect(
          box.inflate(1).contains(line.topLeft) &&
                  box.inflate(1).contains(line.bottomRight) ||
              line.bottom <= box.top + 1,
          isTrue,
          reason: '$line vs $box',
        );
      }
    });

    testWidgets('an edge into a composite without a start meets its box', (
      tester,
    ) async {
      // Wait is written first, but Run is where the box begins
      final chart = await drawn(
        tester,
        'stateDiagram-v2\n  A --> Busy\n  state Busy {\n    Wait\n'
        '    Run --> Wait\n  }\n',
      );
      final box = chart.boxes.single;
      for (final line in chart.lines) {
        expect(
          box.inflate(1).contains(line.topLeft) &&
                  box.inflate(1).contains(line.bottomRight) ||
              line.bottom <= box.top + 1,
          isTrue,
          reason: '$line vs $box',
        );
      }
    });

    testWidgets('a note on a composite is beside its box', (tester) async {
      final chart = await drawn(
        tester,
        'stateDiagram-v2\n  A --> Busy\n  state Busy {\n    Run --> Wait\n'
        '  }\n  note right of Busy : hi\n',
      );
      final box = chart.boxes.single;
      final note = chart.notes.single;
      expect(note.left, greaterThan(box.right));
      expect(note.center.dy, inInclusiveRange(box.top, box.bottom));
    });

    testWidgets('cardinalities are drawn at the ends, on longer lines', (
      tester,
    ) async {
      final plain = await drawn(tester, 'classDiagram\n  A --> B : x\n');
      final counted = await drawn(
        tester,
        'classDiagram\n  A "1" --> "many" B : x\n',
      );
      expect(counted.texts, hasLength(plain.texts.length + 2));
      double gap(_Drawn chart) {
        final [a, b] = chart.nodes..sort((a, b) => a.top.compareTo(b.top));
        return b.top - a.bottom;
      }

      expect(gap(counted), greaterThan(gap(plain) + 10));
    });

    testWidgets('notes are drawn beside their target', (tester) async {
      final chart = await drawn(
        tester,
        'stateDiagram-v2\n  A --> B\n  note right of B : hi\n'
        '  note left of Nobody : dropped\n',
      );
      expect(chart.nodes, hasLength(2));
      // in B's rank, to its right
      final note = chart.notes.single;
      final b = chart.nodes.last;
      expect(note.center.dy, moreOrLessEquals(b.center.dy));
      expect(note.left, greaterThan(b.right));
    });

    testWidgets('a milestone sits at the middle of its span', (tester) async {
      final chart = await drawn(
        tester,
        'gantt\n  A :2024-01-01, 4d\n  M :milestone, 2024-01-01, 4d\n',
      );
      final shapes = [for (final path in chart.fills) path.getBounds()];
      final bar = shapes.firstWhere((r) => r.width > r.height * 2);
      final diamond = shapes.firstWhere(
        (r) => (r.width - r.height).abs() < 0.5,
      );
      expect(diamond.center.dx, moreOrLessEquals(bar.center.dx));
    });

    testWidgets('bang and cloud topics have their own outlines', (
      tester,
    ) async {
      final chart = await drawn(
        tester,
        'mindmap\n  root))Boom((\n    c)Cloudy(\n    s(Smooth)\n',
      );
      // sharp turns along each outline: spikes and the dips between bumps
      int corners(Path path) {
        var count = 0;
        for (final metric in path.computeMetrics()) {
          double? before;
          for (var at = 0.0; at < metric.length; at += 1) {
            final angle = metric.getTangentForOffset(at)!.angle;
            if (before != null) {
              var turn = (angle - before).abs() % (2 * math.pi);
              turn = math.min(turn, 2 * math.pi - turn);
              if (turn > 0.4) count++;
            }
            before = angle;
          }
        }
        return count;
      }

      // children are painted before their parent
      final [cloudy, smooth, boom] = [
        for (final path in chart.fills)
          if (path.getBounds().height > 20) corners(path),
      ];
      expect(boom, greaterThanOrEqualTo(20));
      expect(cloudy, greaterThanOrEqualTo(8));
      expect(smooth, 0);
    });

    testWidgets('a note in a left-to-right chart is truly beside', (
      tester,
    ) async {
      for (final direction in ['LR', 'RL']) {
        final chart = await drawn(
          tester,
          _sideNotes.replaceFirst('direction LR', 'direction $direction'),
        );
        final reason = direction;
        expect(chart.nodes, hasLength(3), reason: reason);
        expect(chart.notes, hasLength(2), reason: reason);
        // A, B, C along the flow
        final byX = [...chart.nodes]..sort((a, b) => a.left.compareTo(b.left));
        final [a, b, c] = direction == 'LR' ? byX : byX.reversed.toList();
        for (final note in chart.notes) {
          // nothing runs through a note or covers it: no point along any
          // line (but its own dotted one, which ends at its side) is inside
          for (final path in chart.linePaths) {
            // the note's own outline and folded corner
            final bounds = path.getBounds();
            if (note.inflate(1).contains(bounds.topLeft) &&
                note.inflate(1).contains(bounds.bottomRight)) {
              continue;
            }
            for (final metric in path.computeMetrics()) {
              for (var at = 0.0; at <= metric.length; at += 2) {
                final point = metric.getTangentForOffset(at)!.position;
                expect(
                  note.deflate(2).contains(point),
                  isFalse,
                  reason: '$reason: $point in $note',
                );
              }
            }
          }
          for (final node in chart.nodes) {
            expect(node.overlaps(note), isFalse, reason: reason);
          }
        }
        if (direction == 'LR') {
          // hi to the right of B, before C; lo to the left of A
          final [lo, hi] = [...chart.notes]
            ..sort((a, b) => a.left.compareTo(b.left));
          expect(hi.left, greaterThan(b.right));
          expect(hi.right, lessThan(c.left));
          expect(lo.right, lessThan(a.left));
          // and level with them
          expect(hi.top, lessThan(b.bottom));
          expect(hi.bottom, greaterThan(b.top));
          expect(lo.top, lessThan(a.bottom));
          expect(lo.bottom, greaterThan(a.top));
        } else {
          // both between B and A, which is on the right
          for (final note in chart.notes) {
            expect(note.left, greaterThan(b.right));
            expect(note.right, lessThan(a.left));
          }
        }
      }
    });

    testWidgets('a note on a composite is level with its top rank', (
      tester,
    ) async {
      // Wait is written first, but Run is on the box's top rank
      final chart = await drawn(
        tester,
        'stateDiagram-v2\n  A --> Busy\n  state Busy {\n    Wait\n'
        '    Run --> Wait\n  }\n  note right of Busy : hi\n',
      );
      final box = chart.boxes.single;
      final inside = chart.nodes.where((n) => box.contains(n.center)).toList()
        ..sort((a, b) => a.top.compareTo(b.top));
      final note = chart.notes.single;
      expect(note.left, greaterThan(box.right));
      expect(note.center.dy, moreOrLessEquals(inside.first.center.dy));
    });

    testWidgets('gantt excluded days are bands', (tester) async {
      var bands = 0;
      await tester.pumpWidget(
        _host(
          const MermaidDiagram(
            'gantt\n  excludes weekends\n  A :2024-01-04, 2d\n'
            '  B :2024-01-09, 1d\n',
          ),
        ),
      );
      expect(
        tester.renderObject(
          find
              .descendant(
                of: find.byType(MermaidDiagram),
                matching: find.byType(CustomPaint),
              )
              .last,
        ),
        paints..everything((method, arguments) {
          if (method == #drawRect &&
              (arguments[1] as Paint).blendMode == BlendMode.srcOver) {
            bands++;
          }
          return true;
        }),
      );
      // Saturday and Sunday, Jan 6 and 7
      expect(bands, 2);
    });

    testWidgets('broken and cut-off diagrams never throw', (tester) async {
      final samples = [
        _flow,
        _subgraphs,
        _sideNotes,
        _states,
        _classes,
        _sequence,
        _er,
        _gantt,
        _mindmap,
        _timeline,
        'pie title Pets\n"Dogs" : 3\n"Cats" : 1\n',
        'gantt\n  dateFormat X\n  excludes weekends\n  A :a, 1704412800, 3d\n'
            '  B :until a\n  C :after a, 2M\n',
        // styling lines
        'flowchart LR\n  A[One]:::hot --> B --> C\n'
            '  classDef hot fill:#f9f,stroke:#333,stroke-width:4px\n'
            '  classDef cold fill:navy,color:white,stroke-dasharray: 5 5\n'
            '  class B,C cold\n  style C fill:#fff8,stroke:teal\n'
            '  linkStyle 0 stroke:#f00,stroke-width:2px\n'
            '  linkStyle default stroke:gray\n',
        'stateDiagram-v2\n  classDef bad fill:#f00,color:white\n'
            '  [*] --> Idle\n  Idle --> Broken:::bad\n  class Idle bad\n',
        'classDiagram\n  class Animal:::soft\n  Animal <|-- Duck\n'
            '  cssClass "Duck" soft\n  classDef soft fill:#eee\n'
            '  style Animal stroke:red\n',
        // the newer kinds
        'gitGraph\n  commit id: "a"\n  branch dev\n  commit tag: "v1"\n'
            '  checkout main\n  commit type: REVERSE\n'
            '  merge dev type: HIGHLIGHT\n',
        'journey\n  title Day\n  section Morning\n    Tea: 5: Me\n'
            '    Work: 1: Me, Cat\n',
        'quadrantChart\n  title Reach\n  x-axis Low --> High\n'
            '  y-axis Bad --> Good\n  quadrant-1 Expand\n  quadrant-3 Drop\n'
            '  A: [0.3, 0.6]\n  B: [0.9, 0.1]\n',
        'sankey-beta\nCoal,Power,30\nGas,Power,10\n'
            'Power,"Homes, all",25\nPower,Coal,5\n',
        'xychart-beta\n  title "Sales"\n  x-axis [jan, feb, mar]\n'
            '  y-axis "Revenue" 0 --> 100\n  bar [25, 50, 100]\n'
            '  line [10, 90, 40]\n',
      ];
      final random = math.Random(7);
      const junk = '[](){}<>|:;-.=o*"%#\n x1u';
      final cases = <String>{};
      for (final sample in samples) {
        final lines = sample.split('\n');
        // cut after every line, at random characters, and with one
        // character swapped for another
        for (var k = 1; k <= lines.length; k++) {
          cases.add(lines.take(k).join('\n'));
        }
        for (var k = 0; k < 15; k++) {
          cases.add(sample.substring(0, random.nextInt(sample.length)));
          final at = random.nextInt(sample.length);
          cases.add(
            sample.replaceRange(at, at + 1, junk[random.nextInt(junk.length)]),
          );
        }
      }
      for (final source in cases) {
        final data = parseMermaid(source);
        await tester.pumpWidget(
          _host(
            MermaidDiagram(
              source,
              key: ValueKey(source),
              fallback: const Text('code'),
            ),
            width: 400,
          ),
        );
        expect(tester.takeException(), isNull, reason: source);
        // code when it isn't read, a picture when it is
        expect(
          find.text('code'),
          data == null ? findsOneWidget : findsNothing,
          reason: source,
        );
        if (data != null) {
          expect(
            find.descendant(
              of: find.byType(MermaidDiagram),
              matching: find.byType(CustomPaint),
            ),
            findsWidgets,
            reason: source,
          );
        }
      }
    });

    testWidgets('new kinds describe themselves', (tester) async {
      const expected = {
        _er:
            'ER diagram: CUSTOMER, Customer order, LINE-ITEM, '
            'DELIVERY-ADDRESS, PRODUCT',
        _gantt: 'Gantt chart Release: Design, Code, Test, Docs, Launch',
        _mindmap: 'Mindmap: Plan, Goals, Speed, Cost, Risks, Scope, Time',
        _timeline:
            'Timeline History: 2002: LinkedIn; '
            '2004: Facebook, Google, Flickr; 2010: Instagram; 2012',
      };
      for (final MapEntry(key: source, value: label) in expected.entries) {
        await tester.pumpWidget(
          _host(MermaidDiagram(source, key: ValueKey(source))),
        );
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
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
            '${e.from}>${e.to} ${e.label} ${e.line.name} ${e.head == EdgeHead.arrow}',
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

    test('a state diagram', () {
      final chart =
          parseMermaid('''
---
title: Order
---
stateDiagram-v2
  direction LR
  [*] --> Idle
  state "Waiting for payment" as Waiting
  Idle --> Waiting : order placed
  Waiting --> Paid: paid
  Waiting --> Idle : timeout %% back edge
  state check <<choice>>
  Paid --> check
  check --> Shipped
  Shipped : Box on the way
  Shipped : tracked
  state Shipped {
    [*] --> Packing
    Packing --> [*]
  }
  note right of Paid : a note
  note left of Idle
    many lines
    Idle --> Nowhere
  end note
  Shipped --> [*]
''')
              as FlowChart;
      expect(chart.kind, FlowKind.state);
      expect(chart.direction, FlowDirection.right);
      expect(chart.nodes.map((n) => '${n.id}|${n.label}|${n.shape.name}'), [
        '[*]start@|<empty>|start'.replaceAll('<empty>', ''),
        'Idle|Idle|rounded',
        'Waiting|Waiting for payment|rounded',
        'Paid|Paid|rounded',
        'check||diamond',
        'Shipped|Box on the way\ntracked|rounded',
        '[*]start@Shipped||start',
        'Packing|Packing|rounded',
        '[*]end@Shipped||end',
        '[*]end@||end',
      ]);
      expect(chart.edges.map((e) => '${e.from}>${e.to} ${e.label}'), [
        '[*]start@>Idle null',
        'Idle>Waiting order placed',
        'Waiting>Paid paid',
        'Waiting>Idle timeout',
        'Paid>check null',
        'check>Shipped null',
        '[*]start@Shipped>Packing null',
        'Packing>[*]end@Shipped null',
        'Shipped>[*]end@ null',
      ]);
    });

    test('a class diagram', () {
      final chart =
          parseMermaid('''
classDiagram
  direction RL
  class Animal {
    <<abstract>>
    +String name
    +int age
    +eat(food) bool
  }
  class Box~T~
  class Empty{}
  Animal <|-- Duck : is a
  Duck : +swim()
  Duck : +String beak
  Zoo "1" *-- "many" Animal : holds
  Zoo o-- Keeper
  Keeper --> Animal
  Duck ..|> Swimmer
  <<interface>> Swimmer
  Box ..> Animal
  Keeper -- Zoo
  Keeper <.. Zoo
''')
              as FlowChart;
      expect(chart.kind, FlowKind.classes);
      expect(chart.direction, FlowDirection.left);
      expect(
        chart.nodes.map(
          (n) =>
              '${n.id}|${n.label}|${n.annotation}|${n.members.join(',')}|'
              '${n.shape.name}',
        ),
        [
          'Animal|Animal|abstract|+String name,+int age,+eat(food) bool|classBox',
          'Box|Box<T>|null||classBox',
          'Empty|Empty|null||classBox',
          'Duck|Duck|null|+swim(),+String beak|classBox',
          'Zoo|Zoo|null||classBox',
          'Keeper|Keeper|null||classBox',
          'Swimmer|Swimmer|interface||classBox',
        ],
      );
      expect(
        chart.edges.map(
          (e) =>
              '${e.from}>${e.to} ${e.label} ${e.line.name} '
              '${e.tail.name}-${e.head.name}',
        ),
        [
          'Animal>Duck is a solid triangle-none',
          'Zoo>Animal holds solid filledDiamond-none',
          'Zoo>Keeper null solid diamond-none',
          'Keeper>Animal null solid none-arrow',
          'Duck>Swimmer null dotted none-triangle',
          'Box>Animal null dotted none-arrow',
          'Keeper>Zoo null solid none-none',
          'Keeper>Zoo null dotted arrow-none',
        ],
      );
    });

    test('flowchart subgraphs', () {
      final chart = parseMermaid(_subgraphs)! as FlowChart;
      expect(
        chart.groups.map(
          (g) => '${g.id}|${g.title}|${g.parent}|${g.members.join(',')}',
        ),
        [
          'one|Back end|null|C',
          'inner|inner|one|D',
          'Front end|Front end|null|E',
          'two|two|null|F,G',
        ],
      );
      // an edge to a subgraph keeps its id as a node; the box is drawn in
      // its place
      expect(chart.nodes.map((n) => n.id), [
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'two',
      ]);
      expect(chart.edges.map((e) => '${e.from}>${e.to}'), [
        'A>B',
        'B>C',
        'F>G',
        'C>two',
        'two>E',
      ]);
      expect(
        (parseMermaid('graph LR\nsubgraph\nA\nend\nB')! as FlowChart).groups
            .map((g) => '${g.title}|${g.members}'),
        ['|[A]'],
      );
    });

    test('composite states and notes', () {
      final chart =
          parseMermaid('''
stateDiagram-v2
  [*] --> Active
  state "Working hard" as Active {
    [*] --> Running
    Running --> Paused
    state Paused {
      [*] --> Held
    }
    note right of Running : busy
  }
  Active --> Done
  note left of Done
    all
    finished
  end note
''')!
              as FlowChart;
      expect(
        chart.groups.map(
          (g) => '${g.id}|${g.title}|${g.parent}|${g.members.join(',')}',
        ),
        [
          'Active|Working hard|null|[*]start@Active,Running,Paused',
          'Paused|Paused|Active|[*]start@Active/Paused,Held',
        ],
      );
      expect(chart.notes.map((n) => '${n.target}|${n.side.name}|${n.text}'), [
        'Running|right|busy',
        'Done|left|all\nfinished',
      ]);
    });

    test('class notes and cardinalities', () {
      final chart =
          parseMermaid('''
classDiagram
  Zoo "1" *-- "0..*" Animal : holds
  Zoo "one" --> Keeper
  Keeper --> "many" Animal
  note for Zoo "open\\ndaily"
  note "floating"
''')!
              as FlowChart;
      expect(chart.edges.map((e) => '${e.fromLabel}|${e.label}|${e.toLabel}'), [
        '1|holds|0..*',
        'one|null|null',
        'null|null|many',
      ]);
      expect(chart.notes.map((n) => '${n.target}|${n.side.name}|${n.text}'), [
        'Zoo|right|open\ndaily',
      ]);
    });

    test('an ER diagram', () {
      final chart = parseMermaid(_er)! as FlowChart;
      expect(chart.kind, FlowKind.entities);
      expect(
        chart.nodes.map(
          (n) => '${n.id}|${n.label}|${n.members.join(',')}|${n.shape.name}',
        ),
        [
          'CUSTOMER|CUSTOMER|string name PK "full name",int age|entity',
          'ORDER|Customer order|int id PK, FK|entity',
          'LINE-ITEM|LINE-ITEM||entity',
          'DELIVERY-ADDRESS|DELIVERY-ADDRESS||entity',
          'PRODUCT|PRODUCT||entity',
        ],
      );
      expect(
        chart.edges.map(
          (e) =>
              '${e.from}>${e.to} ${e.label} ${e.line.name} '
              '${e.tail.name}-${e.head.name}',
        ),
        [
          'CUSTOMER>ORDER places solid one-zeroOrMany',
          'ORDER>LINE-ITEM contains solid one-oneOrMany',
          'CUSTOMER>DELIVERY-ADDRESS uses dotted oneOrMany-one',
          'PRODUCT>LINE-ITEM is in solid zeroOrOne-zeroOrOne',
        ],
      );
      // unknown lines and attributes are left out; an open block still draws
      String entities(String source) => (parseMermaid(source)! as FlowChart)
          .nodes
          .map((n) => '${n.id}:${n.members.join(',')}')
          .join(' ');
      expect(
        entities('erDiagram\n  A ||--o{ B : x\n  what is this\n  excludes x'),
        'A: B:',
      );
      expect(entities('erDiagram\n  A {\n    bad\n    int x\n  }'), 'A:int x');
      expect(entities('erDiagram\n  A {\n    int x'), 'A:int x');
      expect(parseMermaid('erDiagram\n  title Nothing'), isNull);
    });

    test('ER words, quoted names and "to"', () {
      final chart =
          parseMermaid('''
erDiagram
  "Customer Account" only one to zero or many ORDER : places
  ORDER one or more optionally to 1 "Line Item" : has
  A many(0) -- many(1) B : x
  C 1+ .. 0+ D : y
  E zero or one -. one or zero F : z
  G one .- many H : w
  "Customer Account" {
    string name
  }
''')!
              as FlowChart;
      expect(
        chart.edges.map(
          (e) =>
              '${e.from}>${e.to} ${e.label} ${e.line.name} '
              '${e.tail.name}-${e.head.name}',
        ),
        [
          'Customer Account>ORDER places solid one-zeroOrMany',
          'ORDER>Line Item has dotted oneOrMany-one',
          'A>B x solid zeroOrMany-oneOrMany',
          'C>D y dotted oneOrMany-zeroOrMany',
          'E>F z dotted zeroOrOne-zeroOrOne',
          'G>H w dotted one-zeroOrMany',
        ],
      );
      expect(chart.nodes.first.members, ['string name']);
    });

    test('a gantt chart', () {
      final chart = parseMermaid(_gantt)! as GanttChart;
      expect(chart.title, 'Release');
      expect(chart.sections, ['Build', 'Ship']);
      String day(DateTime d) => d.toIso8601String().substring(0, 10);
      expect(
        chart.tasks.map(
          (t) =>
              '${t.name}|${t.id}|${t.section}|${day(t.start)}|${day(t.end)}|'
              '${[if (t.done) 'done', if (t.active) 'active', if (t.critical) 'crit', if (t.milestone) 'milestone'].join(',')}',
        ),
        [
          'Design|a1|Build|2024-01-01|2024-01-04|done',
          'Code|a2|Build|2024-01-04|2024-01-11|active',
          'Test|null|Ship|2024-01-08|2024-01-12|crit',
          'Docs|null|Ship|2024-01-12|2024-01-14|',
          'Launch|m1|Ship|2024-01-15|2024-01-15|milestone',
        ],
      );
      for (final broken in [
        'gantt\n  dateFormat DD-MM-YYYY\n  A :2024-01-01, 1d',
        'gantt\n  A :2024-01-01, 3q',
        'gantt\n  dateFormat X\n  A :2024-01-01, 1d',
        'gantt\n  A :after nothing, 1d',
        'gantt\n  A :2d',
        'gantt\n  A :2024-02-30, 1d',
        'gantt\n  A :2024-01-05, 2024-01-01',
        'gantt\n  A :a, after b, 1d\n  B :b, after a, 1d',
        'gantt\n  just words',
      ]) {
        expect(parseMermaid(broken), isNull, reason: broken);
      }
    });

    test('gantt: forward "after", excludes, inclusive ends, hours', () {
      String show(String source) => (parseMermaid(source)! as GanttChart).tasks
          .map(
            (t) =>
                '${t.name} ${t.start.toIso8601String().substring(5, 16)}'
                '>${t.end.toIso8601String().substring(5, 16)}',
          )
          .join(', ');
      // Jan 5 2024 is a Friday: a day's work runs over the weekend; a span
      // with an end date isn't moved, but inclusiveEndDates takes its last
      // day in
      expect(
        show('''
gantt
  dateFormat YYYY-MM-DD
  excludes weekends
  inclusiveEndDates
  Later :l1, after first, 2d
  First :first, 2024-01-05, 1d
  Fixed :2024-01-05, 2024-01-08
'''),
        'Later 01-08T00:00>01-10T00:00, First 01-05T00:00>01-08T00:00, '
        'Fixed 01-05T00:00>01-09T00:00',
      );
      expect(
        show('''
gantt
  dateFormat YYYY-MM-DD HH:mm
  axisFormat %H:%M
  A :a, 2024-01-01 09:00, 2h
  B :30m
  M :milestone, 2024-01-01 12:00, 1h
'''),
        'A 01-01T09:00>01-01T11:00, B 01-01T11:00>01-01T11:30, '
        'M 01-01T12:00>01-01T13:00',
      );
      expect(
        (parseMermaid('gantt\n  axisFormat %b %e\n  A :2024-01-01, 1d')!
                as GanttChart)
            .axisFormat,
        '%b %e',
      );
      expect(
        formatGanttDate(
          DateTime.utc(2024, 1, 5, 9, 7),
          '%Y-%m-%d %H:%M %b %e %%',
        ),
        '2024-01-05 09:07 Jan 5 %',
      );
      expect(formatGanttDate(DateTime.utc(2024), '%Q'), isNull);
    });

    test('a mindmap', () {
      final map = parseMermaid(_mindmap)! as MindMap;
      String show(MindNode node) =>
          '${node.text}:${node.shape.name}'
          '${node.children.isEmpty ? '' : '(${node.children.map(show).join(' ')})'}';
      expect(
        show(map.root),
        'Plan:circle(Goals:plain(Speed:plain Cost:square) '
        'Risks:plain(Scope:cloud Time:hexagon))',
      );
      expect(parseMermaid('mindmap\n  One\n  Two'), isNull);
      expect(parseMermaid('mindmap\n'), isNull);
    });

    test('a timeline', () {
      final timeline = parseMermaid(_timeline)! as Timeline;
      expect(timeline.title, 'History');
      expect(
        timeline.periods.map(
          (p) => '${p.section}|${p.text}|${p.events.join(',')}',
        ),
        [
          'Early|2002|LinkedIn',
          'Early|2004|Facebook,Google,Flickr',
          'Later|2010|Instagram',
          'Later|2012|',
        ],
      );
      // only a colon with a space after it starts an event
      expect(
        (parseMermaid(
                  'timeline\n  10:30 : Talk: part one : a:b\n  Lunch: 12:00\n',
                )!
                as Timeline)
            .periods
            .map((p) => '${p.text}|${p.events.join(',')}'),
        ['10:30|Talk,part one,a:b', 'Lunch|12:00'],
      );
      expect(parseMermaid('timeline\n  : orphan'), isNull);
      expect(parseMermaid('timeline\n  title Empty'), isNull);
    });

    test('gantt: until, date formats, months and excluded days', () {
      String show(String source) => (parseMermaid(source)! as GanttChart).tasks
          .map(
            (t) =>
                '${t.name} ${t.start.toIso8601String().substring(0, 16)}'
                '>${t.end.toIso8601String().substring(0, 16)}',
          )
          .join(', ');
      // "until" a task further down, which is "after" another
      expect(
        show('''
gantt
  dateFormat D MMM YYYY
  A :a, 5 Jan 2024, until b
  B :b, after c, 1d
  C :c, 8 Jan 2024, 1d
'''),
        'A 2024-01-05T00:00>2024-01-09T00:00, '
        'B 2024-01-09T00:00>2024-01-10T00:00, '
        'C 2024-01-08T00:00>2024-01-09T00:00',
      );
      String start(String format, String date) =>
          show('gantt\n  dateFormat $format\n  A :$date, 1d').substring(2, 18);
      expect(start('MMMM D YY', 'January 5 24'), '2024-01-05T00:00');
      expect(start('M/D/YYYY', '1/5/2024'), '2024-01-05T00:00');
      expect(start('DD.MM.YY', '05.01.99'), '1999-01-05T00:00');
      expect(start('X', '1704412800'), '2024-01-05T00:00');
      expect(start('x', '1704412800000'), '2024-01-05T00:00');
      expect(start('YYYY-MM-DD H:m', '2024-01-05 9:5'), '2024-01-05T09:05');
      expect(start('HH:mm', '09:30'), '1970-01-01T09:30');
      expect(
        parseMermaid('gantt\n  dateFormat Do MMM\n  A :5th Jan, 1d'),
        isNull,
      );
      // months and years by the calendar
      expect(
        show('gantt\n  A :2024-01-31, 1M\n  B :2024-02-29, 1y'),
        'A 2024-01-31T00:00>2024-02-29T00:00, '
        'B 2024-02-29T00:00>2025-02-28T00:00',
      );
      expect(
        (parseMermaid(
                  'gantt\n  excludes weekends, 2024-01-09\n'
                  '  includes 2024-01-07\n  A :2024-01-05, 2024-01-11',
                )!
                as GanttChart)
            .excluded
            .map((d) => d.day),
        [6, 9],
      );
      expect(
        formatGanttDate(
          DateTime.utc(2024, 1, 5, 15, 7),
          '%a %A %B %y %j %I %p',
        ),
        'Fri Friday January 24 005 03 PM',
      );
      expect(formatGanttDate(DateTime.utc(2024, 1, 5), '%I %p'), '12 AM');
    });

    test('ER number names and the MD_PARENT end', () {
      final chart =
          parseMermaid('erDiagram\n  1.5 ||--|| 2 : x\n  A u--o{ B : y\n')!
              as FlowChart;
      expect(chart.nodes.map((n) => n.id), ['1.5', '2', 'A', 'B']);
      expect(
        chart.edges.map(
          (e) => '${e.from}>${e.to} ${e.label} ${e.tail.name}-${e.head.name}',
        ),
        ['1.5>2 x one-one', 'A>B y none-zeroOrMany'],
      );
    });

    test("timelines from Mermaid's own docs", () {
      List<String> read(String source) => [
        for (final p in (parseMermaid(source)! as Timeline).periods)
          '${p.section}|${p.text}|${p.events.join(';')}',
      ];
      expect(
        read('''
timeline
    title History of Social Media Platform
    2002 : LinkedIn
    2004 : Facebook
         : Google
    2005 : YouTube
    2006 : Twitter
'''),
        [
          'null|2002|LinkedIn',
          'null|2004|Facebook;Google',
          'null|2005|YouTube',
          'null|2006|Twitter',
        ],
      );
      expect(
        read('''
timeline
    title Timeline of Industrial Revolution
    section 17th-20th century
        Industry 1.0 : Machinery, Water power, Steam <br>power
        Industry 2.0 : Electricity, Internal combustion engine, Mass production
    section 21st century
        Industry 4.0 : Internet, Robotics, Internet of Things
'''),
        [
          '17th-20th century|Industry 1.0|Machinery, Water power, Steam \npower',
          '17th-20th century|Industry 2.0|'
              'Electricity, Internal combustion engine, Mass production',
          '21st century|Industry 4.0|Internet, Robotics, Internet of Things',
        ],
      );
      final quarters =
          parseMermaid('''
timeline
        title MermaidChart 2023 Timeline
        section 2023 Q1 <br> Release Personal Tier
          Bullet 1 : sub-point 1a : sub-point 1b
               : sub-point 1c
          Bullet 2 : sub-point 2a : sub-point 2b
        section 2023 Q2 <br> Release XYZ Tier
          Bullet 3 : sub-point <br> 3a : sub-point 3b
               : sub-point 3c
''')!
              as Timeline;
      expect(quarters.title, 'MermaidChart 2023 Timeline');
      expect(
        quarters.periods.map(
          (p) => '${p.section}|${p.text}|${p.events.join(';')}',
        ),
        [
          '2023 Q1 \n Release Personal Tier|Bullet 1|'
              'sub-point 1a;sub-point 1b;sub-point 1c',
          '2023 Q1 \n Release Personal Tier|Bullet 2|sub-point 2a;sub-point 2b',
          '2023 Q2 \n Release XYZ Tier|Bullet 3|'
              'sub-point \n 3a;sub-point 3b;sub-point 3c',
        ],
      );
      // a colon is only a separator with a space (or the line's end) after
      // it: in an event "10:30" stays whole, as in Mermaid
      expect(read('timeline\n  Day : starts 10:30 : ends 12:00\n'), [
        'null|Day|starts 10:30;ends 12:00',
      ]);
    });

    test('other diagrams and broken input are not drawn', () {
      expect(parseMermaid('gantt\n  title Plan\n'), isNull);
      expect(parseMermaid(''), isNull);
      expect(parseMermaid('flowchart TD\n'), isNull);
      expect(parseMermaid('pie\n'), isNull);
      expect(parseMermaid('stateDiagram-v2\n'), isNull);
      expect(parseMermaid('classDiagram\n'), isNull);
      // a journey without a task; a kind that isn't drawn
      expect(MermaidDiagram.supports('journey\n  title Day'), isFalse);
      expect(MermaidDiagram.supports('requirementDiagram\n  x'), isFalse);
      expect(MermaidDiagram.supports('erDiagram\n A ||--o{ B : has'), isTrue);
      expect(MermaidDiagram.supports('classDiagram\n A <|-- B'), isTrue);
      expect(MermaidDiagram.supports('graph TD; A-->B'), isTrue);
    });
  });
}
