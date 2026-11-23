import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
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

const _git = '''
gitGraph
  commit id: "init"
  commit
  branch develop
  checkout develop
  commit id: "feat" tag: "v0.1"
  commit type: HIGHLIGHT
  checkout main
  commit type: REVERSE
  merge develop id: "join" tag: "v1.0"
  switch develop
  cherry-pick id: "init"
''';

const _journey = '''
journey
  title My working day
  section Go to work
    Make tea: 5: Me
    Go upstairs: 3: Me
    Do work: 1: Me, Cat
  section Go home
    Go downstairs: 5: Me
    Sit down: 3
''';

const _quadrant = '''
quadrantChart
  title Reach and engagement
  x-axis Low Reach --> High Reach
  y-axis Low Engagement --> High Engagement
  quadrant-1 We should expand
  quadrant-2 Need to promote
  quadrant-3 Re-evaluate
  quadrant-4 May be improved
  Campaign A: [0.25, 0.75]
  Campaign B: [0.5, 0.5]
  Campaign C:::cls: [1.0, 0] radius: 12
''';

const _sankey = '''
sankey-beta

Coal,Power,30
Gas,Power,10
Power,Homes,25
Power,"Industry, heavy",15
''';

const _xy = '''
xychart-beta
  title "Sales Revenue"
  x-axis Month [jan, feb, mar, apr]
  y-axis "Revenue (in \$)" 0 --> 100
  bar [25, 50, 75, 100]
  line [100, 50, 25, 0]
''';

const _samples = [_git, _journey, _quadrant, _sankey, _xy];

typedef _Call = ({Symbol method, List<dynamic> arguments});

// every canvas call the diagram makes
Future<List<_Call>> _calls(WidgetTester tester, String source) async {
  await tester.pumpWidget(_host(MermaidDiagram(source, key: ValueKey(source))));
  expect(tester.takeException(), isNull);
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

bool _filled(Paint paint) =>
    paint.style == PaintingStyle.fill && paint.blendMode == BlendMode.srcOver;

// the circles drawn with a fill of about [radius]: their centers
List<Offset> _dots(List<_Call> calls, double radius) => [
  for (final call in calls)
    if (call.method == #drawCircle &&
        ((call.arguments[1] as double) - radius).abs() < 0.01 &&
        _filled(call.arguments[2] as Paint))
      call.arguments[0] as Offset,
];

List<Rect> _rects(List<_Call> calls, {bool filled = true}) => [
  for (final call in calls)
    if (call.method == #drawRect &&
        _filled(call.arguments[1] as Paint) == filled)
      call.arguments[0] as Rect,
];

List<RRect> _rounded(List<_Call> calls, double radius) => [
  for (final call in calls)
    if (call.method == #drawRRect &&
        _filled(call.arguments[1] as Paint) &&
        (call.arguments[0] as RRect).tlRadiusX == radius)
      call.arguments[0] as RRect,
];

List<(Path, Paint)> _paths(List<_Call> calls, {required bool filled}) => [
  for (final call in calls)
    if (call.method == #drawPath &&
        _filled(call.arguments[1] as Paint) == filled)
      (call.arguments[0] as Path, call.arguments[1] as Paint),
];

Matcher _near(double value, {double epsilon = 0.01}) =>
    moreOrLessEquals(value, epsilon: epsilon);

int _texts(List<_Call> calls) =>
    calls.where((call) => call.method == #drawParagraph).length;

void main() {
  group('reading', () {
    test('a git graph', () {
      final graph = parseMermaid(_git)! as GitGraph;
      expect(graph.branches, ['main', 'develop']);
      expect(graph.commits.map((c) => c.branch), [0, 0, 1, 1, 0, 0, 1]);
      expect(graph.commits.map((c) => c.parents), [
        <int>[],
        [0],
        [1],
        [2],
        [1],
        [4, 3],
        [3],
      ]);
      expect(graph.commits.map((c) => c.label), [
        'init',
        null,
        'feat',
        null,
        null,
        'join',
        null,
      ]);
      expect(graph.commits.map((c) => c.tag), [
        null,
        null,
        'v0.1',
        null,
        null,
        'v1.0',
        'cherry-pick: init',
      ]);
      expect(graph.commits.map((c) => c.type), [
        GitCommitType.normal,
        GitCommitType.normal,
        GitCommitType.normal,
        GitCommitType.highlight,
        GitCommitType.reverse,
        GitCommitType.normal,
        GitCommitType.normal,
      ]);
      expect(graph.commits.map((c) => c.merge), [
        false,
        false,
        false,
        false,
        false,
        true,
        false,
      ]);
    });

    test('git graph: headers, quoted names and lines it can not follow', () {
      for (final head in [
        'gitGraph',
        'gitGraph:',
        'gitGraph LR:',
        'gitGraph TB:',
      ]) {
        expect(
          parseMermaid('$head\n  commit\n'),
          isA<GitGraph>(),
          reason: head,
        );
      }
      final graph =
          parseMermaid(
                'gitGraph\n'
                // nothing to merge, nowhere to go: left out
                '  merge nowhere\n  checkout nowhere\n  merge main\n'
                '  branch "release 1" order: 2\n'
                '  commit id:"a" type: reverse tag: "x" tag: "y" msg: "m"\n'
                '  branch main\n'
                '  commit id: bare\n'
                '  merge "release 1" type: HIGHLIGHT\n'
                '  cherry-pick\n  branch\n  commit type: NOSUCH\n'
                '  frobnicate main\n',
              )!
              as GitGraph;
      expect(graph.branches, ['main', 'release 1']);
      final [a, bare, merge, last] = graph.commits;
      expect(a.branch, 1);
      expect(a.label, 'a');
      expect(a.type, GitCommitType.reverse);
      expect(a.tag, 'x, y');
      expect(a.parents, isEmpty);
      // "branch main" goes back to the branch that is there
      expect(bare.branch, 0);
      expect(bare.label, 'bare');
      expect(merge.parents, [1, 0]);
      expect(merge.merge, isTrue);
      expect(merge.type, GitCommitType.highlight);
      expect(merge.label, isNull);
      expect(last.type, GitCommitType.normal);
      expect(last.parents, [2]);
      expect(parseMermaid('gitGraph\n'), isNull);
      expect(parseMermaid('gitGraph\n  branch a\n  checkout main\n'), isNull);
    });

    test('a user journey', () {
      final journey = parseMermaid(_journey)! as Journey;
      expect(journey.title, 'My working day');
      expect(journey.tasks.map((t) => t.name), [
        'Make tea',
        'Go upstairs',
        'Do work',
        'Go downstairs',
        'Sit down',
      ]);
      expect(journey.tasks.map((t) => t.score), [5, 3, 1, 5, 3]);
      expect(journey.tasks.map((t) => t.actors), [
        ['Me'],
        ['Me'],
        ['Me', 'Cat'],
        ['Me'],
        <String>[],
      ]);
      expect(journey.tasks.map((t) => t.section), [
        'Go to work',
        'Go to work',
        'Go to work',
        'Go home',
        'Go home',
      ]);

      final odd =
          parseMermaid(
                'journey\n  A: 9: x\n  B: 0\n  no score here\n  C: high: x\n'
                '  D: 2:  , y ,\n',
              )!
              as Journey;
      expect(odd.title, isNull);
      // scores are kept between 1 and 5
      expect(odd.tasks.map((t) => (t.name, t.score)), [
        ('A', 5),
        ('B', 1),
        ('D', 2),
      ]);
      expect(odd.tasks.last.actors, ['y']);
      expect(odd.tasks.first.section, isNull);
      expect(parseMermaid('journey\n  title Day\n  section One\n'), isNull);
    });

    test('a quadrant chart', () {
      final chart = parseMermaid(_quadrant)! as QuadrantChart;
      expect(chart.title, 'Reach and engagement');
      expect((chart.xLow, chart.xHigh), ('Low Reach', 'High Reach'));
      expect((chart.yLow, chart.yHigh), ('Low Engagement', 'High Engagement'));
      expect(chart.quadrants, [
        'We should expand',
        'Need to promote',
        'Re-evaluate',
        'May be improved',
      ]);
      expect(chart.points.map((p) => (p.name, p.x, p.y)), [
        ('Campaign A', 0.25, 0.75),
        ('Campaign B', 0.5, 0.5),
        ('Campaign C', 1.0, 0.0),
      ]);

      final odd =
          parseMermaid(
                'quadrantChart\n  x-axis "Only low"\n  y-axis -->\n'
                '  quadrant-3 Three\n  quadrant-5 Five\n'
                '  Far: [7, -2]\n  Bad: [a, 0.5]\n  Short: [0.5]\n',
              )!
              as QuadrantChart;
      expect((odd.xLow, odd.xHigh), ('Only low', null));
      expect((odd.yLow, odd.yHigh), (null, null));
      expect(odd.quadrants, [null, null, 'Three', null]);
      // a point outside the chart is moved to its edge
      expect(odd.points.map((p) => (p.name, p.x, p.y)), [('Far', 1.0, 0.0)]);
      expect(parseMermaid('quadrantChart\n  title Only a title\n'), isNull);
      expect(parseMermaid('quadrantChart\n  quadrant-1 One\n'), isNotNull);
    });

    test('a sankey diagram', () {
      final sankey = parseMermaid(_sankey)! as Sankey;
      expect(sankey.nodes, [
        'Coal',
        'Power',
        'Gas',
        'Homes',
        'Industry, heavy',
      ]);
      expect(sankey.links.map((l) => (l.source, l.target, l.value)), [
        (0, 1, 30.0),
        (2, 1, 10.0),
        (1, 3, 25.0),
        (1, 4, 15.0),
      ]);

      final odd =
          parseMermaid(
                'sankey\n'
                '"He said ""hi""",B,1.5\n'
                'A,B\nA,B,many\nA,B,-1\nA,B,0\nA,A,3\n,B,3\nA,B,1,2\n'
                '"open,B,3\nA,B,1e400\n'
                ' B , C , 2 \n',
              )!
              as Sankey;
      expect(odd.nodes, ['He said "hi"', 'B', 'C']);
      expect(odd.links.map((l) => (l.source, l.target, l.value)), [
        (0, 1, 1.5),
        (1, 2, 2.0),
      ]);
      expect(parseMermaid('sankey-beta\n'), isNull);
      expect(parseMermaid('sankey-beta\nA,B\n'), isNull);
    });

    test('an xy chart', () {
      final chart = parseMermaid(_xy)! as XyChart;
      expect(chart.title, 'Sales Revenue');
      expect(chart.xTitle, 'Month');
      expect(chart.categories, ['jan', 'feb', 'mar', 'apr']);
      expect(chart.xRange, isNull);
      expect(chart.yTitle, r'Revenue (in $)');
      expect(chart.yRange, (0.0, 100.0));
      expect(chart.series.map((s) => s.bar), [true, false]);
      expect(chart.series.map((s) => s.values), [
        [25.0, 50.0, 75.0, 100.0],
        [100.0, 50.0, 25.0, 0.0],
      ]);

      final ranged =
          parseMermaid(
                'xychart horizontal\n  x-axis Year 2020 --> 2023\n'
                '  y-axis Count\n  line "sold" [1, 2.5, -3]\n'
                '  bar [1, two, 3]\n  bar []\n  bar 1, 2\n',
              )!
              as XyChart;
      expect(ranged.title, isNull);
      expect(ranged.xTitle, 'Year');
      expect(ranged.xRange, (2020.0, 2023.0));
      expect(ranged.categories, isNull);
      expect(ranged.yTitle, 'Count');
      expect(ranged.yRange, isNull);
      // a series with a value that is no number is left out whole
      expect(ranged.series.map((s) => s.bar), [false]);
      expect(ranged.series.single.values, [1.0, 2.5, -3.0]);

      final quoted =
          parseMermaid(
                'xychart-beta\n  x-axis ["a, b", c]\n'
                '  y-axis 10 --> 5\n  bar [7, 8]\n',
              )!
              as XyChart;
      expect(quoted.categories, ['a, b', 'c']);
      expect(quoted.xTitle, isNull);
      expect(quoted.yRange, (5.0, 10.0));
      expect(parseMermaid('xychart-beta\n  title Empty\n'), isNull);
    });

    test('supports', () {
      for (final sample in _samples) {
        expect(MermaidDiagram.supports(sample), isTrue, reason: sample);
      }
      expect(MermaidDiagram.supports('gitGraphs\n  commit\n'), isFalse);
      expect(MermaidDiagram.supports('journeys\n  A: 1\n'), isFalse);
      expect(MermaidDiagram.supports('sankey-gamma\nA,B,1\n'), isFalse);
      expect(
        MermaidDiagram.supports('xychart-beta sideways\nbar [1]\n'),
        isFalse,
      );
      expect(MermaidDiagram.supports('requirementDiagram\n'), isFalse);
    });
  });

  group('drawing', () {
    testWidgets('each new kind describes itself', (tester) async {
      const expected = {
        _git: 'Git graph: main, develop; 7 commits',
        _journey:
            'Journey My working day: Make tea 5, Go upstairs 3, Do work 1, '
            'Go downstairs 5, Sit down 3',
        _quadrant:
            'Quadrant chart Reach and engagement: Campaign A, Campaign B, '
            'Campaign C',
        _sankey:
            'Sankey diagram: Coal to Power 30, Gas to Power 10, '
            'Power to Homes 25, Power to Industry, heavy 15',
        _xy: 'XY chart Sales Revenue: bar 25, 50, 75, 100; line 100, 50, 25, 0',
        'quadrantChart\n  quadrant-1 One\n  quadrant-3 Three\n':
            'Quadrant chart: One, Three',
        'xychart-beta\n  line [1.5, 2.25, 1000000]\n':
            'XY chart: line 1.5, 2.25, 1000000',
      };
      for (final MapEntry(key: source, value: label) in expected.entries) {
        await tester.pumpWidget(
          _host(MermaidDiagram(source, key: ValueKey(source))),
        );
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('each new kind fits a narrow width or scrolls', (tester) async {
      for (final source in _samples) {
        await tester.pumpWidget(
          _host(MermaidDiagram(source, key: ValueKey(source)), width: 300),
        );
        expect(tester.takeException(), isNull, reason: source);
        final size = tester.getSize(find.byType(MermaidDiagram));
        expect(size.width, inInclusiveRange(40, 300), reason: source);
        expect(size.height, greaterThan(60), reason: source);
      }
    });

    testWidgets('git graph: lanes, commits, merge lines, tags', (tester) async {
      final calls = await _calls(tester, _git);
      // plain commits are dots: 0, 1 on main, 2 and the cherry-pick on
      // develop
      final dots = _dots(calls, 8);
      expect(dots, hasLength(4));
      expect(dots[0].dy, dots[1].dy);
      expect(dots[2].dy, dots[3].dy);
      expect(dots[2].dy, greaterThan(dots[0].dy + 16));
      // a column each, left to right in the order they were made
      final highlight = _rects(calls).single;
      expect(highlight.size, const Size(16, 16));
      expect(highlight.center.dy, dots[2].dy);
      // the merge commit: a ring around a small dot, on main
      final merge = _dots(calls, 2.6).single;
      expect(merge.dy, dots[0].dy);
      final xs = [dots[0].dx, dots[1].dx, dots[2].dx, highlight.center.dx];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(xs.toSet(), hasLength(4));
      expect(merge.dx, greaterThan(highlight.center.dx));
      expect(dots[3].dx, greaterThan(merge.dx));
      // rings: the reverse commit and the merge commit
      final rings = [
        for (final call in calls)
          if (call.method == #drawCircle &&
              (call.arguments[2] as Paint).style == PaintingStyle.stroke)
            call.arguments[0] as Offset,
      ];
      expect(rings, hasLength(2));
      expect(rings.last, merge);
      expect(rings.first.dx, inExclusiveRange(highlight.center.dx, merge.dx));
      // the reverse commit has a cross: two strokes in one small path
      final strokes = _paths(calls, filled: false);
      final cross = strokes.where((s) => s.$1.computeMetrics().length == 2);
      expect(cross, hasLength(1));
      expect(cross.single.$1.getBounds().center.dx, _near(rings.first.dx));
      // seven lines between commits; the branch-off and the merge change
      // lanes
      final links = [
        for (final (path, paint) in strokes)
          if (paint.strokeWidth == 2) path.getBounds(),
      ];
      expect(links, hasLength(7));
      final bent = links.where((bounds) => bounds.height > 1).toList();
      expect(bent, hasLength(2));
      expect(bent[0].left, _near(dots[1].dx));
      expect(bent[0].right, _near(dots[2].dx));
      expect(bent[1].left, _near(highlight.center.dx));
      expect(bent[1].right, _near(merge.dx));
      // two lane names, three tags above their commits, three ids below
      final names = _rounded(calls, 6);
      expect(names, hasLength(2));
      expect(names[0].center.dy, _near(dots[0].dy));
      expect(names[1].center.dy, _near(dots[2].dy));
      expect(names[0].right, lessThan(dots[0].dx - 8));
      final tags = _rounded(calls, 3);
      expect(tags, hasLength(3));
      expect(tags[0].center.dx, _near(dots[2].dx));
      expect(tags[0].bottom, lessThan(dots[2].dy - 8));
      expect(tags[1].center.dx, _near(merge.dx));
      expect(tags[2].center.dx, _near(dots[3].dx));
      expect(_texts(calls), 8);
      // each lane in its own color
      final colors = [
        for (final call in calls)
          if (call.method == #drawCircle &&
              (call.arguments[1] as double) == 8 &&
              _filled(call.arguments[2] as Paint))
            (call.arguments[2] as Paint).color,
      ];
      expect(colors[0], colors[1]);
      expect(colors[2], colors[3]);
      expect(colors[0], isNot(colors[2]));
    });

    testWidgets('journey: a box per task, a face as high as its score', (
      tester,
    ) async {
      final calls = await _calls(tester, _journey);
      final faces = _dots(calls, 10);
      expect(faces, hasLength(5));
      // scores 5, 3, 1, 5, 3: the better, the higher
      expect(faces[0].dy, faces[3].dy);
      expect(faces[1].dy, faces[4].dy);
      expect(faces[1].dy - faces[0].dy, _near(30));
      expect(faces[2].dy - faces[0].dy, _near(60));
      final xs = faces.map((face) => face.dx).toList();
      expect(xs, orderedEquals([...xs]..sort()));
      // two section bands, then the five task boxes over their faces
      final boxes = _rounded(calls, 6);
      expect(boxes, hasLength(7));
      final [work, home, ...tasks] = boxes;
      expect(work.left, tasks[0].left);
      expect(work.right, tasks[2].right);
      expect(home.left, tasks[3].left);
      expect(home.right, tasks[4].right);
      expect(work.bottom, lessThan(tasks[0].top));
      for (var k = 0; k < 5; k++) {
        expect(tasks[k].center.dx, _near(faces[k].dx));
        expect(tasks[k].bottom, lessThan(faces[k].dy - 10));
        if (k > 0) expect(tasks[k].left, greaterThan(tasks[k - 1].right));
      }
      // the mouths: up at the ends for 5, flat for 3, down for 1
      final mouths = [
        for (final (path, _) in _paths(calls, filled: false))
          if (path.getBounds().width == 9) path.computeMetrics().single,
      ];
      expect(mouths, hasLength(5));
      double bend(int k) =>
          mouths[k].getTangentForOffset(mouths[k].length / 2)!.position.dy -
          mouths[k].getTangentForOffset(0)!.position.dy;
      expect(bend(0), greaterThan(1));
      expect(bend(1).abs(), lessThan(0.01));
      expect(bend(2), lessThan(-1));
      // who took part: a dot per actor on each task, and two in the key
      expect(_dots(calls, 3.5), hasLength(5));
      expect(_dots(calls, 4), hasLength(2));
      // title, 2 actors, 2 sections, 5 names, 5 scores
      expect(_texts(calls), 15);
    });

    testWidgets('quadrant chart: four fields, points where they belong', (
      tester,
    ) async {
      final calls = await _calls(tester, _quadrant);
      final fields = _rects(calls);
      expect(fields, hasLength(4));
      expect(fields.map((r) => r.size), everyElement(const Size(140, 140)));
      final plot = _rects(calls, filled: false).single;
      expect(plot.size, const Size(280, 280));
      // quadrant-1 top right, 2 top left, 3 bottom left, 4 bottom right
      expect(fields[0].topRight, plot.topRight);
      expect(fields[1].topLeft, plot.topLeft);
      expect(fields[2].bottomLeft, plot.bottomLeft);
      expect(fields[3].bottomRight, plot.bottomRight);
      final points = _dots(calls, 4.5);
      expect(points, [
        plot.topLeft + const Offset(70, 70),
        plot.center,
        plot.bottomRight,
      ]);
      // title, 4 names, 3 points, 4 axis ends; the y axis reads upwards
      expect(_texts(calls), 12);
      expect(calls.where((call) => call.method == #rotate), hasLength(2));
      // every text is inside the picture
      final size = tester.getSize(
        find
            .descendant(
              of: find.byType(MermaidDiagram),
              matching: find.byType(CustomPaint),
            )
            .last,
      );
      expect(size.width, greaterThanOrEqualTo(plot.right));
      expect(size.height, greaterThan(plot.bottom + 10));
    });

    testWidgets('sankey: bars and bands as thick as their values', (
      tester,
    ) async {
      final calls = await _calls(tester, _sankey);
      final bars = _rects(calls);
      expect(bars, hasLength(5));
      final [coal, power, gas, homes, industry] = bars;
      expect(bars.map((bar) => bar.width), everyElement(12));
      expect(coal.height / gas.height, _near(3, epsilon: 0.01));
      expect(power.height, _near(coal.height + gas.height, epsilon: 0.01));
      expect(homes.height / industry.height, _near(25 / 15, epsilon: 0.01));
      // the fullest columns (two bars and the gap between) fill the height
      expect(gas.bottom - coal.top, _near(200));
      expect(industry.bottom - homes.top, _near(200));
      expect(power.height, _near(192));
      // three columns
      expect(coal.left, gas.left);
      expect(power.left, greaterThan(coal.right + 40));
      expect(homes.left, greaterThan(power.right + 40));
      expect(homes.left, industry.left);
      expect(gas.top, greaterThan(coal.bottom));
      expect(industry.top, greaterThan(homes.bottom));
      // a band per link, from its source's right side to its target's left
      final bands = _paths(calls, filled: true);
      expect(bands, hasLength(4));
      final ends = [
        (coal, power),
        (gas, power),
        (power, homes),
        (power, industry),
      ];
      for (var k = 0; k < 4; k++) {
        final (from, to) = ends[k];
        final bounds = bands[k].$1.getBounds();
        expect(bounds.left, _near(from.right));
        expect(bounds.right, _near(to.left));
        expect(bands[k].$2.color.a, lessThan(0.5));
      }
      // the bands leaving Power share its side in the order of the rows
      expect(
        bands[2].$1.contains(Offset(power.right + 0.5, power.top + 1)),
        isTrue,
      );
      expect(
        bands[3].$1.contains(Offset(power.right + 0.5, power.top + 1)),
        isFalse,
      );
      expect(
        bands[3].$1.contains(Offset(power.right + 0.5, power.bottom - 1)),
        isTrue,
      );
      expect(
        bands[1].$1.contains(Offset(power.left - 0.5, power.bottom - 1)),
        isTrue,
      );
      expect(_texts(calls), 5);
    });

    testWidgets('sankey: a loop and far apart values still draw', (
      tester,
    ) async {
      for (final source in [
        'sankey-beta\nA,B,1\nB,C,1\nC,A,1\n',
        'sankey-beta\nA,B,1\nB,A,1\n',
        'sankey-beta\nA,B,999999999999\nA,C,0.000001\n',
        'sankey-beta\n${[for (var i = 0; i < 40; i++) 'A,N$i,1'].join('\n')}\n',
      ]) {
        final bars = _rects(await _calls(tester, source));
        for (final bar in bars) {
          expect(
            bar.height.isFinite && bar.height >= 2,
            isTrue,
            reason: source,
          );
          expect(bar.left.isFinite && bar.top.isFinite, isTrue, reason: source);
        }
        final size = tester.getSize(find.byType(MermaidDiagram));
        expect(size.height.isFinite, isTrue);
      }
    });

    testWidgets('xy chart: bars and a line to scale', (tester) async {
      final calls = await _calls(tester, _xy);
      final bars = _rects(calls);
      expect(bars, hasLength(4));
      expect(bars.map((bar) => bar.bottom).toSet(), hasLength(1));
      for (var k = 0; k < 4; k++) {
        expect(bars[k].height, _near(170 * (k + 1) / 4));
        if (k > 0) expect(bars[k].left, greaterThan(bars[k - 1].right));
      }
      // the line: over the middle of each bar, 100 at the top, 0 at the
      // bottom
      final dots = _dots(calls, 3);
      expect(dots, hasLength(4));
      for (var k = 0; k < 4; k++) {
        expect(dots[k].dx, _near(bars[k].center.dx));
      }
      expect(dots[0].dy, _near(bars[3].top));
      expect(dots[1].dy, _near(bars[1].top));
      expect(dots[3].dy, _near(bars[0].bottom));
      final line = _paths(
        calls,
        filled: false,
      ).where((stroke) => stroke.$2.strokeWidth == 2).single;
      final span = line.$1.getBounds();
      expect(span.left, _near(dots.first.dx));
      expect(span.top, _near(dots.first.dy));
      expect(span.right, _near(dots.last.dx));
      expect(span.bottom, _near(dots.last.dy));
      // bar and line in different colors
      final barPaint =
          calls.firstWhere((c) => c.method == #drawRect).arguments[1] as Paint;
      expect(line.$2.color, isNot(barPaint.color));
      // title, 5 ticks, 4 months, 2 axis titles; the y title reads upwards
      expect(_texts(calls), 12);
      expect(calls.where((call) => call.method == #rotate), hasLength(1));
    });

    testWidgets('xy chart: its own range, bars below zero, two bar rows', (
      tester,
    ) async {
      final calls = await _calls(
        tester,
        'xychart-beta\n  bar [5, -5]\n  bar [2.5, 0]\n',
      );
      final [up, down, half, none] = _rects(calls);
      // without a range the chart runs from the lowest value to the
      // highest, and bars stand on zero
      expect(up.height, _near(85));
      expect(down.height, _near(85));
      expect(down.top, _near(up.bottom));
      expect(half.height, _near(42.5));
      expect(half.bottom, _near(up.bottom));
      expect(none.height, 0);
      // the second series stands beside the first
      expect(half.left, _near(up.right));
      expect(none.left, _near(down.right));
      // 5 ticks and the numbers 1 and 2 under the bars
      expect(_texts(calls), 7);

      // values outside the given range stop at its ends
      final clipped = _rects(
        await _calls(
          tester,
          'xychart-beta\n  y-axis 10 --> 20\n  bar [15, 50, 5]\n',
        ),
      );
      expect(clipped.map((bar) => bar.height), [
        _near(85),
        _near(170),
        _near(0),
      ]);
    });

    testWidgets('every prefix of each new kind draws or falls back', (
      tester,
    ) async {
      final random = math.Random(11);
      const junk = '[](){}<>|:;-.=o*"%#\n x1u,';
      final cases = <String>{};
      for (final sample in _samples) {
        for (var end = 0; end <= sample.length; end++) {
          cases.add(sample.substring(0, end));
        }
        for (var k = 0; k < 40; k++) {
          final at = random.nextInt(sample.length);
          cases.add(
            sample.replaceRange(at, at + 1, junk[random.nextInt(junk.length)]),
          );
        }
      }
      var drawn = 0;
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
          drawn++;
          final size = tester.getSize(find.byType(MermaidDiagram));
          expect(size.width.isFinite && size.height.isFinite, isTrue);
        }
      }
      expect(drawn, greaterThan(cases.length ~/ 2));
    });
  });
}
