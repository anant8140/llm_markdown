import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown/src/mermaid/mermaid_model.dart';

const _boundary = ValueKey('boundary');

Widget _host(Widget child, {double width = 800}) => WidgetsApp(
  color: const Color(0xFF2196F3),
  builder: (context, _) => DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF202124)),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: RepaintBoundary(key: _boundary, child: child),
        ),
      ),
    ),
  ),
);

const _styled = '''
flowchart LR
  A[XX]:::hot --> B[XX]
  B --> C[XX]
  C --> D[XX]
  classDef hot fill:#f9f,stroke:#333,stroke-width:4px
  classDef dark fill:#000080,stroke-dasharray: 5 5
  class B dark
  style C fill:#ffffff,color:#ff0000,stroke:blue
  linkStyle 0 stroke:#ff0000,stroke-width:4px,color:blue
  linkStyle 2 stroke-dasharray: 3 3
''';

const _styledState = '''
stateDiagram-v2
  classDef bad fill:#f00,color:white,stroke:yellow
  [*] --> Idle
  Idle --> Broken:::bad : fail
  Idle --> Busy
  class Busy bad
  style Idle fill:gold
''';

const _styledClasses = '''
classDiagram
  class Animal:::soft {
    +String name
  }
  class Duck
  Animal <|-- Duck
  cssClass "Duck" loud
  classDef soft fill:#eee,stroke:#999
  classDef loud fill:#800080
  style Zoo fill:#008080,stroke-width:3px
  Zoo *-- Animal
''';

typedef _Call = ({Symbol method, List<dynamic> arguments});

// every canvas call the diagram makes
Future<List<_Call>> _calls(WidgetTester tester, String source) async {
  await tester.pumpWidget(_host(MermaidDiagram(source, key: ValueKey(source))));
  final calls = <_Call>[];
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
      calls.add((method: method, arguments: arguments));
      return true;
    }),
  );
  return calls;
}

// the paints of the filled node shapes, in the order they were drawn
List<Paint> _nodeFills(List<_Call> calls) => [
  for (final call in calls)
    if (call.method == #drawPath &&
        (call.arguments[1] as Paint).style == PaintingStyle.fill &&
        (call.arguments[0] as Path).getBounds().height > 20)
      call.arguments[1] as Paint,
];

// the outline drawn right after each filled node shape
List<(Path, Paint)> _nodeOutlines(List<_Call> calls) => [
  for (var i = 0; i + 1 < calls.length; i++)
    if (calls[i].method == #drawPath &&
        (calls[i].arguments[1] as Paint).style == PaintingStyle.fill &&
        (calls[i].arguments[0] as Path).getBounds().height > 20)
      (calls[i + 1].arguments[0] as Path, calls[i + 1].arguments[1] as Paint),
];

int _argb(Color color) => color.toARGB32();

// The color of the pixel in the first letter of each painted text, in drawing
// order. The test font draws every letter as a full box, so that pixel has
// the text's color.
Future<List<int>> _textColors(WidgetTester tester, List<_Call> calls) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  final origin =
      tester.getTopLeft(
        find
            .descendant(
              of: find.byType(MermaidDiagram),
              matching: find.byType(CustomPaint),
            )
            .last,
      ) -
      tester.getTopLeft(find.byKey(_boundary));
  late ByteData bytes;
  late int width;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    width = image.width;
    bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
  });
  return [
    for (final call in calls)
      if (call.method == #drawParagraph)
        () {
          final paragraph = call.arguments[0] as ui.Paragraph;
          final at =
              origin +
              (call.arguments[1] as Offset) +
              // the middle of the first of the line's two letters
              Offset(
                paragraph.width / 2 - paragraph.longestLine / 4,
                paragraph.height / 2,
              );
          final i = (at.dy.round() * width + at.dx.round()) * 4;
          return bytes.getUint8(i + 3) << 24 |
              bytes.getUint8(i) << 16 |
              bytes.getUint8(i + 1) << 8 |
              bytes.getUint8(i + 2);
        }(),
  ];
}

void main() {
  group('reading styles', () {
    test('colors: hex forms and names', () {
      expect(parseCssColor('#f9f'), 0xFFFF99FF);
      expect(parseCssColor('#F9F8'), 0x88FF99FF);
      expect(parseCssColor('#336699'), 0xFF336699);
      expect(parseCssColor(' #33669980 '), 0x80336699);
      const names = {
        'red': 0xFFFF0000,
        'green': 0xFF008000,
        'blue': 0xFF0000FF,
        'yellow': 0xFFFFFF00,
        'orange': 0xFFFFA500,
        'purple': 0xFF800080,
        'pink': 0xFFFFC0CB,
        'gray': 0xFF808080,
        'grey': 0xFF808080,
        'black': 0xFF000000,
        'white': 0xFFFFFFFF,
        'cyan': 0xFF00FFFF,
        'magenta': 0xFFFF00FF,
        'brown': 0xFFA52A2A,
        'teal': 0xFF008080,
        'navy': 0xFF000080,
        'lime': 0xFF00FF00,
        'gold': 0xFFFFD700,
        'silver': 0xFFC0C0C0,
        'transparent': 0x00000000,
      };
      for (final MapEntry(key: name, value: color) in names.entries) {
        expect(parseCssColor(name), color, reason: name);
      }
      expect(parseCssColor('Red'), 0xFFFF0000);
      for (final bad in [
        '',
        '#',
        '#12',
        '#12345',
        '#1234567',
        '#ggg',
        'rgb(1',
        'nosuchcolor',
        '#123456789',
      ]) {
        expect(parseCssColor(bad), isNull, reason: bad);
      }
    });

    test('classDef, class, ":::" and style on a flowchart', () {
      final chart = parseMermaid(_styled)! as FlowChart;
      final [a, b, c, d] = chart.nodes;
      expect(chart.nodes.map((n) => n.label), everyElement('XX'));
      expect(a.style!.fill, 0xFFFF99FF);
      expect(a.style!.stroke, 0xFF333333);
      expect(a.style!.strokeWidth, 4);
      expect(a.style!.color, isNull);
      expect(a.style!.dashed, isNull);
      expect(b.style!.fill, 0xFF000080);
      expect(b.style!.dashed, isTrue);
      expect(b.style!.stroke, isNull);
      expect(c.style!.fill, 0xFFFFFFFF);
      expect(c.style!.color, 0xFFFF0000);
      expect(c.style!.stroke, 0xFF0000FF);
      expect(d.style, isNull);
      // the styling lines made no nodes of their own
      expect(chart.nodes, hasLength(4));
      expect(chart.edges, hasLength(3));
    });

    test('linkStyle by number, by list and default', () {
      final chart = parseMermaid(_styled)! as FlowChart;
      final [first, second, third] = chart.edges;
      expect(first.style!.stroke, 0xFFFF0000);
      expect(first.style!.strokeWidth, 4);
      expect(first.style!.color, 0xFF0000FF);
      expect(second.style, isNull);
      expect(third.style!.dashed, isTrue);
      expect(third.style!.stroke, isNull);
      // the edge itself is as it was
      expect(first.from, 'A');
      expect(first.to, 'B');
      expect(first.head, EdgeHead.arrow);

      final all =
          parseMermaid(
                'graph TD\n  A -- yes --> B\n  B -.-> C\n  C --> A\n'
                '  linkStyle default stroke:green\n'
                '  linkStyle 1,2 stroke-width:3px\n'
                '  linkStyle 2 interpolate basis stroke:#00f\n'
                '  linkStyle 9 stroke:red\n',
              )!
              as FlowChart;
      expect(all.edges.map((e) => e.style!.stroke), [
        0xFF008000,
        0xFF008000,
        0xFF0000FF,
      ]);
      expect(all.edges.map((e) => e.style!.strokeWidth), [null, 3, 3]);
      expect(all.edges[0].label, 'yes');
      expect(all.edges[1].line, EdgeLine.dotted);
    });

    test('order: default class, classes in turn, then style', () {
      final chart =
          parseMermaid(
                'flowchart TD\n'
                // used before they are defined
                '  class A,B one\n'
                '  A:::two --> B --> C\n'
                '  style B stroke:#111,fill:#222\n'
                '  classDef default fill:#abc,stroke-width:1px\n'
                '  classDef one,three fill:red,color:white\n'
                '  classDef two fill:blue\n'
                '  classDef one stroke:lime\n'
                '  class C nosuchclass\n'
                '  style Nobody fill:red\n',
              )!
              as FlowChart;
      final [a, b, c] = chart.nodes;
      // A: default, then one, then two
      expect(a.style!.fill, 0xFF0000FF);
      expect(a.style!.color, 0xFFFFFFFF);
      expect(a.style!.stroke, 0xFF00FF00);
      expect(a.style!.strokeWidth, 1);
      // B: its style line wins over its class
      expect(b.style!.fill, 0xFF222222);
      expect(b.style!.stroke, 0xFF111111);
      expect(b.style!.color, 0xFFFFFFFF);
      // C: only the default class
      expect(c.style!.fill, 0xFFAABBCC);
      expect(c.style!.color, isNull);
      expect(chart.nodes, hasLength(3));
    });

    test('unknown properties and bad values are left out', () {
      final chart =
          parseMermaid(
                'flowchart TD\n  A --> B --> C --> D\n'
                '  style A fill:#12,stroke:#333,font-size:20px,rx:5\n'
                '  style B fill:nosuch,opacity:0.5\n'
                '  style C stroke-width:wide,stroke-dasharray:0,fill:#fff;\n'
                '  style D stroke-width:99px,stroke-dasharray:none\n'
                '  style\n  classDef\n  class A\n  linkStyle\n'
                '  linkStyle x stroke:red\n  classDef only\n',
              )!
              as FlowChart;
      final [a, b, c, d] = chart.nodes;
      expect(a.style!.fill, isNull);
      expect(a.style!.stroke, 0xFF333333);
      // nothing readable: no style at all
      expect(b.style, isNull);
      expect(c.style!.strokeWidth, isNull);
      expect(c.style!.dashed, isFalse);
      expect(c.style!.fill, 0xFFFFFFFF);
      // a width is capped
      expect(d.style!.strokeWidth, 12);
      expect(d.style!.dashed, isFalse);
      expect(chart.nodes, hasLength(4));
      expect(chart.edges, hasLength(3));
      expect(chart.edges.map((e) => e.style), everyElement(isNull));
    });

    test('a diagram without styling lines has no styles', () {
      final chart = parseMermaid('graph TD\n  A --> B\n')! as FlowChart;
      expect(chart.nodes.map((n) => n.style), everyElement(isNull));
      expect(chart.edges.map((e) => e.style), everyElement(isNull));
    });

    test('state diagrams: classDef, class, ":::" and style', () {
      final chart = parseMermaid(_styledState)! as FlowChart;
      final byId = {for (final node in chart.nodes) node.id: node};
      expect(byId.keys, ['[*]start@', 'Idle', 'Broken', 'Busy']);
      for (final id in ['Broken', 'Busy']) {
        expect(byId[id]!.style!.fill, 0xFFFF0000, reason: id);
        expect(byId[id]!.style!.color, 0xFFFFFFFF, reason: id);
        expect(byId[id]!.style!.stroke, 0xFFFFFF00, reason: id);
      }
      expect(byId['Idle']!.style!.fill, 0xFFFFD700);
      expect(byId['[*]start@']!.style, isNull);
      // ":::bad" is not part of the transition
      expect(chart.edges[1].to, 'Broken');
      expect(chart.edges[1].label, 'fail');
    });

    test('class diagrams: ":::", cssClass, classDef and style', () {
      final chart = parseMermaid(_styledClasses)! as FlowChart;
      final byId = {for (final node in chart.nodes) node.id: node};
      expect(byId.keys, ['Animal', 'Duck', 'Zoo']);
      expect(byId['Animal']!.style!.fill, 0xFFEEEEEE);
      expect(byId['Animal']!.style!.stroke, 0xFF999999);
      expect(byId['Animal']!.members, ['+String name']);
      expect(byId['Duck']!.style!.fill, 0xFF800080);
      expect(byId['Zoo']!.style!.fill, 0xFF008080);
      expect(byId['Zoo']!.style!.strokeWidth, 3);
      expect(chart.edges, hasLength(2));
    });
  });

  group('drawing styles', () {
    testWidgets('nodes are filled and outlined in their own colors', (
      tester,
    ) async {
      final calls = await _calls(tester, _styled);
      final fills = _nodeFills(calls);
      expect(fills.map((paint) => _argb(paint.color)), [
        0xFFFF99FF,
        0xFF000080,
        0xFFFFFFFF,
        // D is in the theme's color
        isNot(anyOf(0xFFFF99FF, 0xFF000080, 0xFFFFFFFF)),
      ]);
      final outlines = _nodeOutlines(calls);
      expect(outlines, hasLength(4));
      final [a, b, c, d] = outlines;
      expect(a.$2.style, PaintingStyle.stroke);
      expect(_argb(a.$2.color), 0xFF333333);
      expect(a.$2.strokeWidth, 4);
      expect(_argb(c.$2.color), 0xFF0000FF);
      expect(c.$2.strokeWidth, d.$2.strokeWidth);
      expect(d.$2.strokeWidth, closeTo(1.4, 1e-6));
      expect(_argb(b.$2.color), _argb(d.$2.color));
      // only B's outline is dashed: many short strokes
      expect(b.$1.computeMetrics().length, greaterThan(8));
      for (final solid in [a, c, d]) {
        expect(solid.$1.computeMetrics().length, 1);
      }
    });

    testWidgets('text on a fill is black or white, or the given color', (
      tester,
    ) async {
      final calls = await _calls(tester, _styled);
      final colors = await _textColors(tester, calls);
      // A on pink, B on navy, C red as told, D in the theme's color
      expect(colors, [0xFF000000, 0xFFFFFFFF, 0xFFFF0000, 0xFF202124]);

      // a see-through fill keeps the theme's text color; "color" still
      // wins
      final more = await _calls(
        tester,
        'graph LR\n  A[XX] --> B[XX] --> C[XX] --> D[XX]\n'
        '  style A fill:#00000020\n  style B fill:#ffffff20,color:#00ff00\n'
        '  style C fill:#555\n  style D fill:yellow\n',
      );
      expect(await _textColors(tester, more), [
        // not the white a solid black fill would get
        0xFF202124,
        0xFF00FF00,
        0xFFFFFFFF,
        0xFF000000,
      ]);
    });

    testWidgets('linkStyle colors, widens and dashes an edge', (tester) async {
      final calls = await _calls(tester, _styled);
      final fills = _nodeFills(calls).toSet();
      final nodeOutlines = _nodeOutlines(calls).map((o) => o.$2).toSet();
      final strokes = [
        for (final call in calls)
          if (call.method == #drawPath &&
              (call.arguments[1] as Paint).style == PaintingStyle.stroke &&
              !nodeOutlines.contains(call.arguments[1]))
            (call.arguments[0] as Path, call.arguments[1] as Paint),
      ];
      expect(strokes, hasLength(3));
      final [first, second, third] = strokes;
      expect(_argb(first.$2.color), 0xFFFF0000);
      expect(first.$2.strokeWidth, 4);
      expect(first.$1.computeMetrics().length, 1);
      expect(second.$2.strokeWidth, closeTo(1.4, 1e-6));
      expect(_argb(second.$2.color), isNot(0xFFFF0000));
      expect(second.$1.computeMetrics().length, 1);
      // dashed, in the theme's line color
      expect(_argb(third.$2.color), _argb(second.$2.color));
      expect(third.$1.computeMetrics().length, greaterThan(2));
      // the arrow heads: small filled paths, the first one red too
      final heads = [
        for (final call in calls)
          if (call.method == #drawPath &&
              (call.arguments[1] as Paint).style == PaintingStyle.fill &&
              !fills.contains(call.arguments[1]))
            _argb((call.arguments[1] as Paint).color),
      ];
      expect(heads, [0xFFFF0000, _argb(second.$2.color), heads.last]);
      expect(heads.last, _argb(second.$2.color));
    });

    testWidgets('state and class boxes take their colors too', (tester) async {
      final states = _nodeFills(await _calls(tester, _styledState));
      expect(
        states.map((paint) => _argb(paint.color)),
        containsAll([0xFFFF0000, 0xFFFFD700]),
      );
      expect(
        states.where((paint) => _argb(paint.color) == 0xFFFF0000),
        hasLength(2),
      );
      final calls = await _calls(tester, _styledClasses);
      expect(_nodeFills(calls).map((paint) => _argb(paint.color)).toSet(), {
        0xFFEEEEEE,
        0xFF800080,
        0xFF008080,
      });
      final zoo = _nodeOutlines(
        calls,
      ).firstWhere((outline) => outline.$2.strokeWidth == 3);
      expect(zoo.$2.style, PaintingStyle.stroke);
      // a class name on purple is white, on pale gray black
      final colors = await _textColors(tester, calls);
      expect(colors, containsAll([0xFFFFFFFF, 0xFF000000]));
      expect(colors, everyElement(anyOf(0xFF000000, 0xFFFFFFFF)));
    });

    testWidgets('stroke-width:0 draws no outline', (tester) async {
      final calls = await _calls(
        tester,
        'graph TD\n  A[XX]\n  style A stroke-width:0,stroke:red\n',
      );
      final outline = _nodeOutlines(calls).single.$2;
      expect(outline.color.a, 0);
    });

    testWidgets('every prefix of a styled diagram draws or falls back', (
      tester,
    ) async {
      for (final sample in [_styled, _styledState, _styledClasses]) {
        for (var end = 0; end <= sample.length; end++) {
          final source = sample.substring(0, end);
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
          expect(
            find.text('code'),
            data == null ? findsOneWidget : findsNothing,
            reason: source,
          );
        }
      }
    });
  });
}
