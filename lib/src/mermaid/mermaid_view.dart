import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../direction.dart';
import '../style.dart';
import 'mermaid_model.dart';

/// Draws a Mermaid diagram natively.
///
/// `StreamingMarkdown` uses it for ` ```mermaid ` code blocks. Drawn kinds:
/// flowcharts (with `subgraph` boxes), state diagrams (with composite
/// states and notes), class diagrams (with notes and cardinalities), ER
/// diagrams, sequence diagrams, pie charts, gantt charts (`YYYY-MM-DD`
/// dates, day and week spans), mindmaps, timelines, git graphs
/// (`gitGraph`), user journeys, quadrant charts, sankey diagrams and xy
/// charts. Other kinds, and text these readers can't follow, are not
/// drawn: [supports] is false for them and [fallback] is shown.
///
/// Flowcharts, state and class diagrams take the diagram's own colors
/// from `classDef`, `class`, `:::`, `style` and (flowcharts) `linkStyle`:
/// fill, stroke, stroke-width, color and stroke-dasharray. Icons and
/// other CSS are left out.
class MermaidDiagram extends StatefulWidget {
  /// Draws the diagram written in [source].
  const MermaidDiagram(this.source, {super.key, this.style, this.fallback});

  /// The Mermaid text.
  final String source;

  /// The colors and text style; defaults to [StreamingMarkdownStyle.of].
  final StreamingMarkdownStyle? style;

  /// Shown when [source] isn't a diagram this widget draws.
  final Widget? fallback;

  /// Whether [source] is a diagram this widget draws.
  static bool supports(String source) => parseMermaid(source) != null;

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  _Scene? _scene;
  Object? _sceneKey;

  @override
  void dispose() {
    _scene?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? StreamingMarkdownStyle.of(context);
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final key = (widget.source, style, scaler, direction);
    if (key != _sceneKey) {
      _sceneKey = key;
      _scene?.dispose();
      final data = parseMermaid(widget.source);
      _scene = data == null
          ? null
          : _SceneBuilder(style, scaler, direction).build(data);
    }
    final scene = _scene;
    if (scene == null) return widget.fallback ?? const SizedBox.shrink();
    return Semantics(
      image: true,
      label: scene.description,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A wide diagram shrinks to fit, but only while it stays
            // readable; past that it scrolls sideways.
            final available = constraints.maxWidth;
            final scale = available.isFinite
                ? (available / scene.size.width).clamp(_smallestScale, 1.0)
                : 1.0;
            final paint = CustomPaint(
              size: scene.size * scale,
              painter: _ScenePainter(scene, scale),
            );
            if (scene.size.width * scale <= available + 0.5) {
              return Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: paint,
              );
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: paint,
            );
          },
        ),
      ),
    );
  }
}

const double _smallestScale = 0.6;

class _Scene {
  _Scene(this.size, this.ops, this.painters, this.description);

  final Size size;
  final List<void Function(Canvas canvas)> ops;
  final List<TextPainter> painters;
  final String description;

  void dispose() {
    for (final painter in painters) {
      painter.dispose();
    }
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.scale);

  final _Scene scene;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // its own layer, so an edge label can erase the bit of line under it
    // without erasing what is behind the diagram
    canvas
      ..saveLayer(Offset.zero & size, Paint())
      ..scale(scale);
    for (final op in scene.ops) {
      op(canvas);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) =>
      !identical(oldDelegate.scene, scene) || oldDelegate.scale != scale;
}

const double _pad = 8;

// distinct on light and dark backgrounds
const List<Color> _palette = [
  Color(0xFF4C8BF5),
  Color(0xFFF2994A),
  Color(0xFF27AE60),
  Color(0xFFEB5757),
  Color(0xFF9B51E0),
  Color(0xFF2DB5C4),
  Color(0xFFF2C94C),
  Color(0xFF8D99AE),
];

class _SceneBuilder {
  _SceneBuilder(this.style, this.scaler, this.direction)
    : look = style.diagramStyle,
      text =
          style.diagramStyle.textStyle?.color ??
          style.textStyle.color ??
          const Color(0xFF808080),
      labelStyle = style.textStyle
          .copyWith(
            fontSize: (style.textStyle.fontSize ?? 14) * 0.9,
            height: 1.25,
          )
          .merge(style.diagramStyle.textStyle);

  final MarkdownDiagramStyle look;

  final StreamingMarkdownStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final Color text;
  final TextStyle labelStyle;

  final List<void Function(Canvas)> ops = [];
  final List<TextPainter> painters = [];

  Color get line => look.lineColor ?? text.withValues(alpha: 0.6);
  Color get fill => look.nodeColor ?? style.accentColor.withValues(alpha: 0.1);
  Color get border =>
      look.nodeBorderColor ?? style.accentColor.withValues(alpha: 0.7);

  TextPainter measure(
    String label, {
    TextStyle? style,
    double maxWidth = 220,
    TextAlign align = TextAlign.center,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style ?? labelStyle),
      textAlign: align,
      textDirection: detectTextDirection(label) ?? direction,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
    painters.add(painter);
    return painter;
  }

  void drawText(TextPainter painter, Offset center) {
    final at = center - Offset(painter.width / 2, painter.height / 2);
    ops.add((canvas) => painter.paint(canvas, at));
  }

  Paint stroke(Color color, [double width = 1.4]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..color = color;

  void drawPath(Path path, Paint paint, {bool dashed = false}) {
    final drawn = dashed ? _dash(path) : path;
    ops.add((canvas) => canvas.drawPath(drawn, paint));
  }

  // an arrow head with its tip at [tip], pointing along [angle]
  void drawHead(Offset tip, double angle, Color color) {
    const length = 9.0;
    const spread = 0.45;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - length * math.cos(angle - spread),
        tip.dy - length * math.sin(angle - spread),
      )
      ..lineTo(
        tip.dx - length * math.cos(angle + spread),
        tip.dy - length * math.sin(angle + spread),
      )
      ..close();
    final paint = Paint()..color = color;
    ops.add((canvas) => canvas.drawPath(path, paint));
  }

  // the end of an edge: an arrow, the hollow triangle of inheritance, or a
  // diamond; [tip] touches the node and [angle] points into it
  void drawMarker(EdgeHead kind, Offset tip, double angle, Color color) {
    if (kind == EdgeHead.none) return;
    if (kind == EdgeHead.arrow) return drawHead(tip, angle, color);
    Offset back(double length, [double side = 0]) =>
        tip -
        Offset(math.cos(angle), math.sin(angle)) * length +
        Offset(-math.sin(angle), math.cos(angle)) * side;
    if (kind.index >= EdgeHead.one.index) return _crowFoot(kind, back, color);
    final path = Path()..moveTo(tip.dx, tip.dy);
    if (kind == EdgeHead.triangle) {
      final a = back(12, 7);
      final b = back(12, -7);
      path
        ..lineTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    } else {
      final a = back(8, 5);
      final c = back(16);
      final b = back(8, -5);
      path
        ..lineTo(a.dx, a.dy)
        ..lineTo(c.dx, c.dy)
        ..lineTo(b.dx, b.dy);
    }
    path.close();
    final filled = kind == EdgeHead.filledDiamond;
    // a hollow one is cleared first, so the line under it doesn't show
    final inside = filled
        ? (Paint()..color = color)
        : (Paint()..blendMode = BlendMode.clear);
    final outline = stroke(color, 1.3);
    ops.add(
      (canvas) => canvas
        ..drawPath(path, inside)
        ..drawPath(path, outline),
    );
  }

  // An ER end: a bar for "one", a ring for "zero", three prongs for "many";
  // the mark nearest the node is the most, the other the least.
  void _crowFoot(
    EdgeHead kind,
    Offset Function(double length, [double side]) back,
    Color color,
  ) {
    final pen = stroke(color, 1.3);
    final marks = Path();
    void bar(double at) {
      final a = back(at, 6);
      final b = back(at, -6);
      marks
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }

    final many = kind == EdgeHead.oneOrMany || kind == EdgeHead.zeroOrMany;
    if (many) {
      final root = back(12);
      for (final side in [7.0, -7.0]) {
        final prong = back(0, side);
        marks
          ..moveTo(root.dx, root.dy)
          ..lineTo(prong.dx, prong.dy);
      }
    } else {
      bar(6);
    }
    Rect? ring;
    if (kind == EdgeHead.zeroOrOne || kind == EdgeHead.zeroOrMany) {
      ring = Rect.fromCircle(center: back(many ? 18 : 14), radius: 4);
    } else {
      bar(many ? 16 : 11);
    }
    final clear = Paint()..blendMode = BlendMode.clear;
    ops.add((canvas) {
      canvas.drawPath(marks, pen);
      if (ring != null) {
        canvas
          ..drawOval(ring, clear)
          ..drawOval(ring, pen);
      }
    });
  }

  // The color of the text in a node the diagram styles: its "color", or
  // black or white, whichever reads better on its fill. Null (the theme's
  // text color) without a fill, and on a fill more than half see-through,
  // where what is behind the diagram shows.
  static Color? _textOn(FlowStyle? style) {
    final own = style?.color;
    if (own != null) return Color(own);
    final fill = style?.fill;
    if (fill == null || Color(fill).a < 0.5) return null;
    return Color(fill).computeLuminance() > 0.179
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
  }

  _Scene build(MermaidData data) {
    final (size, description) = switch (data) {
      FlowChart() => _flow(data),
      SequenceDiagram() => _sequence(data),
      PieChart() => _pie(data),
      GanttChart() => _gantt(data),
      MindMap() => _mindmap(data),
      Timeline() => _timeline(data),
      GitGraph() => _gitGraph(data),
      Journey() => _journey(data),
      QuadrantChart() => _quadrant(data),
      Sankey() => _sankey(data),
      XyChart() => _xyChart(data),
    };
    return _Scene(size, ops, painters, description);
  }

  // ---- flowchart ----------------------------------------------------

  (Size, String) _flow(FlowChart chart) {
    // Subgraphs and composite states are drawn as titled boxes. A composite
    // (a group whose id is also a node) isn't drawn as a node: an edge to
    // it is laid out to the first node inside it (its start dot, if any),
    // an edge from it from the last (its end dot), and both are drawn to
    // the box's side.
    final groups = chart.groups;
    final groupOf = {for (var g = 0; g < groups.length; g++) groups[g].id: g};
    final byId = {for (final node in chart.nodes) node.id: node};
    String? endOf(int g, {required bool entry, int depth = 0}) {
      if (depth > groups.length) return null;
      final group = groups[g];
      final members = [
        for (final id in group.members)
          if (id != group.id && byId.containsKey(id)) id,
      ];
      if (members.isEmpty) {
        final child = groups.indexWhere((c) => c.parent == group.id);
        return child == -1
            ? null
            : endOf(child, entry: entry, depth: depth + 1);
      }
      final marker = entry ? NodeShape.start : NodeShape.end;
      // without a start (end) dot: a node nothing inside leads into (out
      // of), so an edge to the box meets the top of what is in it
      final open = [
        for (final id in members)
          if (!chart.edges.any(
            (e) =>
                (entry ? e.to : e.from) == id &&
                members.contains(entry ? e.from : e.to) &&
                e.from != e.to,
          ))
            id,
      ];
      final pick =
          members.where((id) => byId[id]!.shape == marker).firstOrNull ??
          (entry ? open.firstOrNull : open.lastOrNull) ??
          (entry ? members.first : members.last);
      final inner = groupOf[pick];
      return (inner == null
              ? null
              : endOf(inner, entry: entry, depth: depth + 1)) ??
          pick;
    }

    final composite = {
      for (final node in chart.nodes)
        if (groupOf[node.id] case final g? when endOf(g, entry: true) != null)
          node.id,
    };
    String inside(String id, {required bool entry}) =>
        composite.contains(id) ? endOf(groupOf[id]!, entry: entry)! : id;

    final nodes = composite.isEmpty
        ? chart.nodes
        : [
            for (final node in chart.nodes)
              if (!composite.contains(node.id)) node,
          ];
    final index = {for (var i = 0; i < nodes.length; i++) nodes[i].id: i};
    final edges = <(int, int, FlowEdge)>[];
    // the composite each end of an edge is drawn to, if any
    final boxEnds = <(int?, int?)>[];
    for (final edge in chart.edges) {
      final from = inside(edge.from, entry: false);
      final to = inside(edge.to, entry: true);
      if (from == to) continue;
      edges.add((index[from]!, index[to]!, edge));
      boxEnds.add((
        composite.contains(edge.from) ? groupOf[edge.from] : null,
        composite.contains(edge.to) ? groupOf[edge.to] : null,
      ));
    }

    // the groups each laid out item (node, lane stop, note) is in,
    // outermost first
    final memberOf = <String, int>{};
    for (var g = 0; g < groups.length; g++) {
      for (final id in groups[g].members) {
        memberOf.putIfAbsent(id, () => g);
      }
    }
    List<int> chainOf(int? group) {
      final chain = <int>[];
      for (var at = group; at != null && chain.length <= groups.length;) {
        chain.insert(0, at);
        final parent = groups[at].parent;
        at = parent == null ? null : groupOf[parent];
      }
      return chain;
    }

    final chains = [for (final node in nodes) chainOf(memberOf[node.id])];
    final boxed = chains.any((chain) => chain.isNotEmpty);
    List<int> shared(List<int> a, List<int> b) {
      var k = 0;
      while (k < a.length && k < b.length && a[k] == b[k]) {
        k++;
      }
      return a.sublist(0, k);
    }

    // edges that close a cycle point backwards and don't push ranks down
    final back = <int>{};
    final state = List.filled(nodes.length, 0);
    void visit(int node) {
      state[node] = 1;
      for (var i = 0; i < edges.length; i++) {
        if (edges[i].$1 != node) continue;
        final next = edges[i].$2;
        if (state[next] == 1) {
          back.add(i);
        } else if (state[next] == 0) {
          visit(next);
        }
      }
      state[node] = 2;
    }

    for (var i = 0; i < nodes.length; i++) {
      if (state[i] == 0) visit(i);
    }
    final rank = List.filled(nodes.length, 0);
    for (var round = 0; round < nodes.length; round++) {
      var moved = false;
      for (var i = 0; i < edges.length; i++) {
        if (back.contains(i)) continue;
        final (from, to, _) = edges[i];
        if (rank[to] < rank[from] + 1) {
          rank[to] = rank[from] + 1;
          moved = true;
        }
      }
      if (!moved) break;
    }
    var rankCount = rank.fold(0, math.max) + 1;

    // A transition that loops back up out of a composite leaves from the
    // top of its box (laid out from the first nodes inside, not the last),
    // and one looping back up into it arrives at the bottom.
    for (final i in back) {
      final (from, to, edge) = edges[i];
      final (fromBox, toBox) = boxEnds[i];
      var low = to;
      var high = from;
      if (fromBox != null) {
        final entry = index[endOf(fromBox, entry: true)]!;
        if (rank[entry] > rank[low]) high = entry;
      }
      if (toBox != null) {
        final exit = index[endOf(toBox, entry: false)]!;
        if (rank[exit] < rank[high]) low = exit;
      }
      edges[i] = (high, low, edge);
    }

    // Notes. Its target is kept as a node index, or -1 - group for a box.
    final noteTargets = <int>[];
    final noteTexts = <TextPainter>[];
    final noteStyle = labelStyle.copyWith(
      fontSize: (labelStyle.fontSize ?? 13) * 0.88,
    );
    // the nodes of a composite's box, and their ranks
    List<int> inBox(int g) => [
      for (var i = 0; i < nodes.length; i++)
        if (chains[i].contains(g)) i,
    ];
    final sideways =
        chart.direction == FlowDirection.right ||
        chart.direction == FlowDirection.left;
    final backwards =
        chart.direction == FlowDirection.up ||
        chart.direction == FlowDirection.left;
    // In a left-to-right (or right-to-left) chart a note gets a rank of its
    // own just after (or before) its target's, so it sits truly to the
    // target's right (or left); an edge across that rank gets a lane there
    // like across any other. (target, the rank after which its rank goes,
    // the node it is beside, its text)
    final sideNotes = <(int, int, int, FlowNote)>[];
    if (sideways) {
      final slots = <int>{};
      for (final note in chart.notes) {
        if (!byId.containsKey(note.target)) continue;
        final after = (note.side == NoteSide.right) != backwards;
        final int target;
        final List<int> beside;
        if (composite.contains(note.target)) {
          final g = groupOf[note.target]!;
          target = -1 - g;
          beside = inBox(g);
        } else {
          target = index[note.target]!;
          beside = [target];
        }
        final ranks = beside.map((i) => rank[i]);
        final edge = after ? ranks.reduce(math.max) : ranks.reduce(math.min);
        final slot = after ? edge : edge - 1;
        slots.add(slot);
        sideNotes.add((
          target,
          slot,
          beside.firstWhere((i) => rank[i] == edge),
          note,
        ));
      }
      if (slots.isNotEmpty) {
        int moved(int r) => r + slots.where((slot) => slot < r).length;
        for (var i = 0; i < nodes.length; i++) {
          rank[i] = moved(rank[i]);
        }
        rankCount += slots.length;
        for (var k = 0; k < sideNotes.length; k++) {
          final (target, slot, beside, note) = sideNotes[k];
          // the slot's own rank: just after where rank [slot] went
          sideNotes[k] = (target, moved(slot + 1) - 1, beside, note);
        }
      }
    }

    // An edge that skips ranks gets an invisible stop in each rank between,
    // so it is given its own lane there and runs beside the nodes, not
    // through them. Edges that point backwards are laid out the other way
    // round and only drawn with the arrow at the other end.
    final layoutRank = [...rank];
    final segments = <(int, int)>[];
    final routes = <List<int>>[];
    for (var i = 0; i < edges.length; i++) {
      final (from, to, _) = edges[i];
      final low = back.contains(i) ? to : from;
      final high = back.contains(i) ? from : to;
      final route = [low];
      for (var r = rank[low] + 1; r < rank[high]; r++) {
        layoutRank.add(r);
        // a lane between two nodes of a group stays in the group
        chains.add(shared(chains[low], chains[high]));
        segments.add((route.last, layoutRank.length - 1));
        route.add(layoutRank.length - 1);
      }
      segments.add((route.last, high));
      route.add(high);
      routes.add(route);
    }
    // the notes beside, in their own ranks, take part in the ordering:
    // each is drawn toward the node it is beside
    final firstNote = layoutRank.length;
    final noteBeside = <int, int>{};
    for (final (target, noteRank, beside, note) in sideNotes) {
      layoutRank.add(noteRank);
      chains.add(
        target < 0 ? (chainOf(-1 - target)..removeLast()) : chains[target],
      );
      segments.add((beside, layoutRank.length - 1));
      noteBeside[layoutRank.length - 1] = beside;
      noteTargets.add(target);
      noteTexts.add(
        measure(
          note.text,
          style: noteStyle,
          maxWidth: 160,
          align: TextAlign.start,
        ),
      );
    }
    final count = layoutRank.length;
    final rows = [
      for (var r = 0; r < rankCount; r++)
        [
          for (var i = 0; i < count; i++)
            if (layoutRank[i] == r) i,
        ],
    ];

    // put each node near the middle of its neighbors in the row before
    final position = List.filled(count, 0.0);
    void place(List<int> row) {
      for (var i = 0; i < row.length; i++) {
        position[row[i]] = i.toDouble();
      }
    }

    // With groups, the nodes of one group are kept side by side in a row,
    // so its box holds no one else's: the row is ordered by where each
    // group (its members' mean) wants to be, then inside it.
    void order(List<int> row, Map<int, double> wanted) {
      if (!boxed) {
        row.sort((a, b) {
          final byWanted = wanted[a]!.compareTo(wanted[b]!);
          if (byWanted != 0) return byWanted;
          // a note beside goes level with its node, ahead of lanes there
          if (noteBeside.isNotEmpty) {
            final notes = (noteBeside.containsKey(a) ? 0 : 1).compareTo(
              noteBeside.containsKey(b) ? 0 : 1,
            );
            if (notes != 0) return notes;
          }
          return a.compareTo(b);
        });
        return;
      }
      final sum = <int, double>{};
      final size = <int, int>{};
      for (final node in row) {
        for (final g in chains[node]) {
          sum[g] = (sum[g] ?? 0) + wanted[node]!;
          size[g] = (size[g] ?? 0) + 1;
        }
      }
      row.sort((a, b) {
        final ca = chains[a];
        final cb = chains[b];
        for (var k = 0; ; k++) {
          final ga = k < ca.length ? ca[k] : null;
          final gb = k < cb.length ? cb[k] : null;
          if (ga != null && ga == gb) continue;
          final wa = ga == null ? wanted[a]! : sum[ga]! / size[ga]!;
          final wb = gb == null ? wanted[b]! : sum[gb]! / size[gb]!;
          final byWanted = wa.compareTo(wb);
          if (byWanted != 0) return byWanted;
          if (ga == null && gb == null && noteBeside.isNotEmpty) {
            final notes = (noteBeside.containsKey(a) ? 0 : 1).compareTo(
              noteBeside.containsKey(b) ? 0 : 1,
            );
            if (notes != 0) return notes;
          }
          return (ga == null ? a : -1 - ga).compareTo(gb == null ? b : -1 - gb);
        }
      });
    }

    rows.forEach(place);
    void sweep(Iterable<int> ranks, int step) {
      for (final r in ranks) {
        final row = rows[r];
        final wanted = <int, double>{};
        for (final node in row) {
          final near = [
            for (final (low, high) in segments)
              if (low == node && layoutRank[high] == r + step)
                position[high]
              else if (high == node && layoutRank[low] == r + step)
                position[low],
          ];
          final beside = noteBeside[node];
          wanted[node] = beside != null
              ? position[beside]
              : near.isEmpty
              ? position[node]
              : near.reduce((a, b) => a + b) / near.length;
        }
        order(row, wanted);
        place(row);
      }
    }

    for (var i = 0; i < 2; i++) {
      sweep(Iterable.generate(rankCount - 1, (r) => r + 1), -1);
      sweep(Iterable.generate(rankCount - 1, (r) => rankCount - 2 - r), 1);
    }
    if (boxed) {
      // every row once more, so a row no sweep reached is grouped too
      for (final row in rows) {
        order(row, {for (final node in row) node: position[node]});
        place(row);
      }
    }

    // In a top-to-bottom chart a note goes in its target's rank, just after
    // it in the row (just before for "left of"). A note on a composite goes
    // beside its box, in the box's top rank.
    for (final note in sideways ? const <FlowNote>[] : chart.notes) {
      if (!byId.containsKey(note.target)) continue;
      final at = layoutRank.length;
      final left = note.side == NoteSide.left;
      if (composite.contains(note.target)) {
        final g = groupOf[note.target]!;
        final ranks = inBox(g).map((i) => layoutRank[i]);
        final top = backwards ? ranks.reduce(math.max) : ranks.reduce(math.min);
        final row = rows[top];
        final here = [
          for (var k = 0; k < row.length; k++)
            if (chains[row[k]].contains(g)) k,
        ];
        layoutRank.add(top);
        chains.add(chainOf(g)..removeLast());
        row.insert(left ? here.first : here.last + 1, at);
        noteTargets.add(-1 - g);
      } else {
        final target = index[inside(note.target, entry: true)]!;
        layoutRank.add(layoutRank[target]);
        chains.add(chains[target]);
        final row = rows[layoutRank[target]];
        final k = row.indexOf(target);
        row.insert(left ? k : k + 1, at);
        noteTargets.add(target);
      }
      noteTexts.add(
        measure(
          note.text,
          style: noteStyle,
          maxWidth: 160,
          align: TextAlign.start,
        ),
      );
    }
    final total = layoutRank.length;
    bool isLane(int i) => i >= nodes.length && i < firstNote;

    final labels = [
      for (final node in nodes)
        measure(
          node.label,
          style: labelStyle.copyWith(color: _textOn(node.style)),
        ),
    ];
    final classes = {
      for (var i = 0; i < nodes.length; i++)
        if (nodes[i].shape == NodeShape.classBox ||
            nodes[i].shape == NodeShape.entity)
          i: _classParts(nodes[i]),
    };
    const lane = Size(14, 14);
    final sizes = [
      for (var i = 0; i < total; i++)
        i >= firstNote
            ? noteTexts[i - firstNote].size + const Offset(22, 14)
            : i >= nodes.length
            ? lane
            : classes[i]?.size ?? _nodeSize(nodes[i].shape, labels[i].size),
    ];

    final horizontal =
        chart.direction == FlowDirection.right ||
        chart.direction == FlowDirection.left;
    final flipped =
        chart.direction == FlowDirection.up ||
        chart.direction == FlowDirection.left;
    // "along" runs from rank to rank, "across" inside a rank
    double along(Size size) => horizontal ? size.width : size.height;
    double across(Size size) => horizontal ? size.height : size.width;

    // room for group boxes: their padding and the title along their top
    final titleStyle = labelStyle.copyWith(
      fontSize: (labelStyle.fontSize ?? 13) * 0.85,
      fontWeight: FontWeight.w600,
      color: text.withValues(alpha: 0.75),
    );
    final titleHeight = boxed ? measure('Ag', style: titleStyle).height : 0.0;
    // a box is at least as wide as its title
    final titles = <int, TextPainter>{};
    if (boxed) {
      for (var g = 0; g < groups.length; g++) {
        final title = groups[g].title;
        if (title.isEmpty) continue;
        final painter = titles[g] = TextPainter(
          text: TextSpan(text: title, style: titleStyle),
          textDirection: detectTextDirection(title) ?? direction,
          textScaler: scaler,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 480);
        painters.add(painter);
      }
    }
    double titleRoom(int g) => (titles[g]?.width ?? 0) + _pad * 2;
    final depth = chains.map((chain) => chain.length).fold(0, math.max);
    final boundaryGap = _pad * 2 + (horizontal ? titleHeight + 4 : 0);
    // ER ends carry crow's feet at both ends, and class ends may carry
    // cardinalities beside the middle label, so their lines are longer
    final rankGap =
        (chart.kind == FlowKind.entities ||
                chart.edges.any(
                  (edge) => edge.fromLabel != null || edge.toLabel != null,
                )
            ? 64.0
            : 44.0) +
        (boxed ? depth * (_pad * 2 + (horizontal ? 0 : titleHeight + 4)) : 0.0);
    const nodeGap = 28.0;
    final inset = boxed ? depth * (_pad + titleHeight + 4) : 0.0;
    double gapAfter(int a, int b) {
      final common = shared(chains[a], chains[b]).length;
      return nodeGap +
          (chains[a].length + chains[b].length - common * 2) * boundaryGap;
    }

    final rankStart = <double>[];
    final rankSize = <double>[];
    var cursor = 0.0;
    for (final row in rows) {
      final thickness = row
          .where((i) => !isLane(i))
          .map((i) => along(sizes[i]))
          .fold(0.0, math.max);
      rankStart.add(cursor);
      rankSize.add(thickness);
      cursor += thickness + rankGap;
    }
    var totalAlong = cursor - rankGap;
    final rowWidths = [
      for (final row in rows)
        boxed
            ? row.map((i) => across(sizes[i])).fold(0.0, (a, b) => a + b) +
                  [
                    for (var k = 1; k < row.length; k++)
                      gapAfter(row[k - 1], row[k]),
                  ].fold(0.0, (a, b) => a + b)
            : row.map((i) => across(sizes[i])).fold(0.0, (a, b) => a + b) +
                  nodeGap * math.max(0, row.length - 1),
    ];
    var totalAcross = rowWidths.fold(0.0, math.max);

    // from (along, across) to the canvas
    Offset point(double a, double c) {
      final placed = flipped ? totalAlong - a : a;
      return horizontal
          ? Offset(placed + _pad + inset, c + _pad + inset)
          : Offset(c + _pad + inset, placed + _pad + inset);
    }

    final acrossOf = List.filled(total, 0.0);
    for (var r = 0; r < rows.length; r++) {
      var at = (totalAcross - rowWidths[r]) / 2;
      final row = rows[r];
      for (var k = 0; k < row.length; k++) {
        final i = row[k];
        acrossOf[i] = at + across(sizes[i]) / 2;
        at +=
            across(sizes[i]) +
            (boxed && k + 1 < row.length ? gapAfter(i, row[k + 1]) : nodeGap);
      }
    }
    if (boxed) {
      // A group's box spans all its ranks, so a node of another group (or
      // none) in one of those ranks is moved sideways out of the box, with
      // the rest of its row beyond it.
      final rowOf = [for (final i in Iterable.generate(total)) layoutRank[i]];
      for (var pass = 0; pass < 3; pass++) {
        var moved = false;
        for (var g = 0; g < groups.length; g++) {
          final members = [
            for (var i = 0; i < total; i++)
              if (chains[i].contains(g)) i,
          ];
          if (members.isEmpty) continue;
          // its box, roughly: nested boxes and padding included
          final margin =
              (depth - chainOf(g).length + 1) * boundaryGap + nodeGap / 2;
          final low =
              members
                  .map((i) => acrossOf[i] - across(sizes[i]) / 2)
                  .reduce(math.min) -
              margin;
          final high = math.max(
            members
                    .map((i) => acrossOf[i] + across(sizes[i]) / 2)
                    .reduce(math.max) +
                margin,
            // a box widened for its title, in a top-to-bottom chart
            horizontal ? 0.0 : low + titleRoom(g) + nodeGap,
          );
          final ranks = members.map((i) => rowOf[i]);
          final first = ranks.reduce(math.min);
          final last = ranks.reduce(math.max);
          for (var r = first; r <= last; r++) {
            final row = rows[r];
            for (var k = 0; k < row.length; k++) {
              final i = row[k];
              if (chains[i].contains(g)) continue;
              final start = acrossOf[i] - across(sizes[i]) / 2;
              final end = acrossOf[i] + across(sizes[i]) / 2;
              if (end <= low || start >= high) continue;
              // out the side its row puts it on (or, in a row without the
              // group, the nearer side), taking its neighbors along
              final inRow = [
                for (var j = 0; j < row.length; j++)
                  if (chains[row[j]].contains(g)) j,
              ];
              final right = inRow.isEmpty
                  ? acrossOf[i] > (low + high) / 2
                  : k > inRow.first;
              final by = right ? high - start : low - end;
              for (final j in right ? row.sublist(k) : row.sublist(0, k + 1)) {
                acrossOf[j] += by;
              }
              moved = true;
            }
          }
        }
        if (!moved) break;
      }
      // back to starting at zero
      final left = [
        for (var i = 0; i < total; i++) acrossOf[i] - across(sizes[i]) / 2,
      ].reduce(math.min);
      for (var i = 0; i < total; i++) {
        acrossOf[i] -= left;
      }
      totalAcross = [
        for (var i = 0; i < total; i++) acrossOf[i] + across(sizes[i]) / 2,
      ].reduce(math.max);
    }
    // a note beside goes level with its node, as far as its neighbors in
    // its row (lanes too) leave room
    for (final MapEntry(key: note, value: beside) in noteBeside.entries) {
      final row = rows[layoutRank[note]];
      final k = row.indexOf(note);
      final half = across(sizes[note]) / 2;
      var low = half;
      var high = totalAcross - half;
      if (k > 0) {
        final before = row[k - 1];
        low = math.max(
          low,
          acrossOf[before] + across(sizes[before]) / 2 + nodeGap + half,
        );
      }
      if (k + 1 < row.length) {
        final after = row[k + 1];
        high = math.min(
          high,
          acrossOf[after] - across(sizes[after]) / 2 - nodeGap - half,
        );
      }
      if (low <= high) acrossOf[note] = acrossOf[beside].clamp(low, high);
    }
    double middleOf(int node) =>
        rankStart[layoutRank[node]] + rankSize[layoutRank[node]] / 2;
    Rect rectOf(int i) => Rect.fromCenter(
      center: point(middleOf(i), acrossOf[i]),
      width: sizes[i].width,
      height: sizes[i].height,
    );

    // the group boxes, innermost first, each around its own nodes and notes
    // and the boxes inside it; drawn under everything else, outermost first
    final boxes = <int, RRect>{};
    final tint = Paint()..color = fill.withValues(alpha: fill.a * 0.5);
    final boxLine = stroke(border.withValues(alpha: border.a * 0.5), 1);
    final drawOrder = [for (var g = 0; g < groups.length; g++) g]
      ..sort((a, b) => chainOf(a).length.compareTo(chainOf(b).length));
    // how much each box was widened for its title
    final widened = <int, double>{};
    final titleSpots = <(TextPainter, Offset)>[];
    void measureBoxes() {
      boxes.clear();
      widened.clear();
      for (final g in drawOrder.reversed) {
        Rect? area;
        for (var i = 0; i < total; i++) {
          if (isLane(i) || chains[i].lastOrNull != g) continue;
          area = area?.expandToInclude(rectOf(i)) ?? rectOf(i);
        }
        for (var c = 0; c < groups.length; c++) {
          final inner = boxes[c];
          if (inner == null || groups[c].parent != groups[g].id) continue;
          area = area?.expandToInclude(inner.outerRect) ?? inner.outerRect;
        }
        if (area == null) continue;
        var rect = Rect.fromLTRB(
          area.left - _pad,
          area.top - _pad - titleHeight - 4,
          area.right + _pad,
          area.bottom + _pad,
        );
        // widened toward the later ranks (or just rightward)
        final short = titleRoom(g) - rect.width;
        if (short > 0) {
          widened[g] = short;
          rect = horizontal && flipped
              ? Rect.fromLTRB(
                  rect.left - short,
                  rect.top,
                  rect.right,
                  rect.bottom,
                )
              : Rect.fromLTRB(
                  rect.left,
                  rect.top,
                  rect.right + short,
                  rect.bottom,
                );
        }
        boxes[g] = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      }
    }

    if (boxed) {
      measureBoxes();
      // In a left-to-right chart a box is widened along the ranks, so the
      // ranks after it move along to make room.
      final made = <int>{};
      while (horizontal) {
        final g = widened.keys.where((g) => !made.contains(g)).firstOrNull;
        if (g == null) break;
        made.add(g);
        final last = [
          for (var i = 0; i < total; i++)
            if (!isLane(i) && chains[i].contains(g)) layoutRank[i],
        ].fold(0, math.max);
        for (var r = last + 1; r < rankStart.length; r++) {
          rankStart[r] += widened[g]!;
        }
        totalAlong += widened[g]!;
        measureBoxes();
      }
      for (final g in drawOrder) {
        final box = boxes[g];
        if (box == null) continue;
        ops.add(
          (canvas) => canvas
            ..drawRRect(box, tint)
            ..drawRRect(box, boxLine),
        );
        final painter = titles[g];
        if (painter == null) continue;
        // written after the edges, so none runs over it
        titleSpots.add((painter, Offset(box.left + _pad, box.top + 5)));
      }
    }
    // where a box starts and ends, from rank to rank
    (double, double) alongSpan(Rect rect) {
      double back(double v) {
        final a = v - _pad - inset;
        return flipped ? totalAlong - a : a;
      }

      final a = back(horizontal ? rect.left : rect.top);
      final b = back(horizontal ? rect.right : rect.bottom);
      return (math.min(a, b), math.max(a, b));
    }

    // room for edge labels drawn beside the lines, and for boxes widened
    // past the nodes
    var extra = 0.0;
    var below = 0.0;
    // and for labels pushed past the top or left edge
    var above = 0.0;
    var before = 0.0;
    for (final box in boxes.values) {
      extra = math.max(extra, box.right);
      below = math.max(below, box.bottom);
    }
    final edgeLabels = <(TextPainter, Offset)>[];
    var pairLabels = 0;
    final edgePaint = stroke(line);
    // In class and ER diagrams the ends carry triangles, diamonds and
    // crow's feet, so edges that leave or reach the same side of a box are
    // spread along it instead of sharing one point. Key: (edge, true for
    // its low end).
    final spread = <(int, bool), double>{};
    // In flowcharts and state diagrams, edges between the same two nodes
    // (one each way, or more) are spread too, with the other edges on the
    // sides they leave or reach, so they run clear of each other: on a
    // tie, those along the flow first.
    final linked =
        chart.kind == FlowKind.classes || chart.kind == FlowKind.entities;
    final paired = <int>{};
    if (!linked) {
      final byEnds = <(int, int), List<int>>{};
      for (var i = 0; i < edges.length; i++) {
        byEnds.putIfAbsent((routes[i].first, routes[i].last), () => []).add(i);
      }
      for (final list in byEnds.values) {
        if (list.length > 1) paired.addAll(list);
      }
    }
    if (linked || paired.isNotEmpty) {
      final sides = <(int, bool), List<int>>{};
      for (var i = 0; i < edges.length; i++) {
        sides.putIfAbsent((routes[i].first, true), () => []).add(i);
        sides.putIfAbsent((routes[i].last, false), () => []).add(i);
      }
      for (final MapEntry(key: (node, low), value: list) in sides.entries) {
        if (list.length < 2) continue;
        if (!linked && !list.any(paired.contains)) continue;
        // ordered by where the other end is, so the lines don't cross
        double toward(int i) {
          final route = routes[i];
          return acrossOf[low ? route[1] : route[route.length - 2]];
        }

        if (linked) {
          list.sort((a, b) => toward(a).compareTo(toward(b)));
        } else {
          list.sort((a, b) {
            final byToward = toward(a).compareTo(toward(b));
            if (byToward != 0) return byToward;
            final against = (back.contains(a) ? 1 : 0).compareTo(
              back.contains(b) ? 1 : 0,
            );
            return against != 0 ? against : a.compareTo(b);
          });
        }
        // (a pair needs room to stay apart even on a low box; an end on a
        // composite's box has the box's width)
        var room = across(sizes[node]);
        if (!linked) {
          for (final i in list) {
            final (fromBox, toBox) = boxEnds[i];
            final box =
                boxes[(low == back.contains(i) ? toBox : fromBox) ?? -1];
            if (box != null) room = math.max(room, across(box.outerRect.size));
          }
        }
        final step = linked
            ? math.min(28.0, (across(sizes[node]) - 16) / list.length)
            : math.min(28.0, math.max(0.0, room - 10) / (list.length - 1));
        for (var k = 0; k < list.length; k++) {
          spread[(list[k], low)] = (k - (list.length - 1) / 2) * step;
        }
      }
    }
    final endStyle = labelStyle.copyWith(
      fontSize: (labelStyle.fontSize ?? 13) * 0.8,
      color: text.withValues(alpha: 0.8),
    );
    for (var i = 0; i < edges.length; i++) {
      final edge = edges[i].$3;
      final route = routes[i];
      final reversed = back.contains(i);
      final low = route.first;
      final high = route.last;
      // an edge drawn against the flow sits a little to the side, so it
      // doesn't hide the edge going the other way
      double shift(int node) =>
          (reversed && !paired.contains(i)
              ? math.min(10.0, math.max(0, across(sizes[node]) / 2 - 8))
              : 0) +
          (spread[(i, node == low)] ?? 0);
      final stops = <(double, double)>[
        (
          middleOf(low) +
              along(sizes[low]) / 2 -
              _inset(nodes[low].shape, sizes[low], shift(low), horizontal),
          acrossOf[low] + shift(low),
        ),
        for (final stop in route.sublist(1, route.length - 1)) ...[
          (rankStart[layoutRank[stop]], acrossOf[stop]),
          (
            rankStart[layoutRank[stop]] + rankSize[layoutRank[stop]],
            acrossOf[stop],
          ),
        ],
        (
          middleOf(high) -
              along(sizes[high]) / 2 +
              _inset(nodes[high].shape, sizes[high], shift(high), horizontal),
          acrossOf[high] + shift(high),
        ),
      ];
      if (boxed) {
        // an edge to or from a composite ends on its box, when the box is
        // on the edge's way
        final (fromBox, toBox) = boxEnds[i];
        final lowBox = boxes[(reversed ? toBox : fromBox) ?? -1];
        final highBox = boxes[(reversed ? fromBox : toBox) ?? -1];
        if (lowBox != null) {
          final (_, far) = alongSpan(lowBox.outerRect);
          if (far < stops[1].$1) stops.first = (far, stops.first.$2);
        }
        if (highBox != null) {
          final (near, _) = alongSpan(highBox.outerRect);
          if (near > stops[stops.length - 2].$1) {
            stops.last = (near, stops.last.$2);
          }
        }
      }
      final first = point(stops.first.$1, stops.first.$2);
      final path = Path()..moveTo(first.dx, first.dy);
      for (var k = 1; k < stops.length; k++) {
        final (a0, c0) = stops[k - 1];
        final (a1, c1) = stops[k];
        final end = point(a1, c1);
        if (c0 == c1) {
          path.lineTo(end.dx, end.dy);
        } else {
          // a soft S between two lanes
          final c1Point = point((a0 + a1) / 2, c0);
          final c2Point = point((a0 + a1) / 2, c1);
          path.cubicTo(
            c1Point.dx,
            c1Point.dy,
            c2Point.dx,
            c2Point.dy,
            end.dx,
            end.dy,
          );
        }
      }
      // a linkStyle line gives the edge its own color, width and dashes
      final own = edge.style;
      final ownStroke = own?.stroke;
      final edgeColor = ownStroke == null ? line : Color(ownStroke);
      final thick = edge.line == EdgeLine.thick;
      drawPath(
        path,
        own == null
            ? (thick ? stroke(line, 2.6) : edgePaint)
            : stroke(
                edgeColor,
                math.max(0.5, own.strokeWidth ?? (thick ? 2.6 : 1.4)),
              ),
        dashed: edge.line == EdgeLine.dotted || own?.dashed == true,
      );
      // the route runs from low to high, so a reversed edge has its head at
      // the start of the route and its tail at the end
      final forward = (point(1, 0) - point(0, 0)).direction;
      final last = point(stops.last.$1, stops.last.$2);
      drawMarker(
        edge.head,
        reversed ? first : last,
        reversed ? forward + math.pi : forward,
        edgeColor,
      );
      drawMarker(
        edge.tail,
        reversed ? last : first,
        reversed ? forward : forward + math.pi,
        edgeColor,
      );
      // cardinalities sit beside each end, clear of the line and markers,
      // on the side away from the middle of the box
      for (final (cardinality, atLow) in [
        (edge.fromLabel, !reversed),
        (edge.toLabel, reversed),
      ]) {
        if (cardinality == null) continue;
        final painter = measure(cardinality, style: endStyle, maxWidth: 100);
        final (a, c) = atLow ? stops.first : stops.last;
        final side = shift(atLow ? low : high) < 0 ? -1.0 : 1.0;
        final center = point(
          a + (atLow ? 1 : -1) * (4 + along(painter.size) / 2),
          c + side * (across(painter.size) / 2 + 7),
        );
        drawText(painter, center);
        extra = math.max(extra, center.dx + painter.width / 2);
        below = math.max(below, center.dy + painter.height / 2);
        above = math.min(above, center.dy - painter.height / 2);
        before = math.min(before, center.dx - painter.width / 2);
      }
      final label = edge.label;
      if (label != null) {
        final painter = measure(
          label,
          style: labelStyle
              .copyWith(
                fontSize: (labelStyle.fontSize ?? 13) * 0.9,
                color: text.withValues(alpha: 0.8),
              )
              .merge(look.edgeLabelStyle)
              .copyWith(color: own?.color == null ? null : Color(own!.color!)),
          maxWidth: 140,
        );
        // on the middle of the edge's middle stretch, as Mermaid does
        final k = stops.length ~/ 2;
        var center =
            (point(stops[k - 1].$1, stops[k - 1].$2) +
                point(stops[k].$1, stops[k].$2)) /
            2;
        // one of a pair goes beside its own line, on that line's side, so
        // the two labels don't land on each other or on the other line
        final side = paired.contains(i) ? (reversed ? 1.0 : -1.0) : 0.0;
        if (side != 0) {
          // clear of the line over the label's whole height: an S between
          // two lanes runs across fastest at its middle, twice its mean
          final (a0, c0) = stops[k - 1];
          final (a1, c1) = stops[k];
          final slope = a1 == a0 ? 0.0 : 2 * (c1 - c0).abs() / (a1 - a0).abs();
          final sideways = point(0, 1) - point(0, 0);
          center +=
              sideways *
              side *
              (across(painter.size) / 2 +
                  6 +
                  math.min(40.0, slope * along(painter.size) / 2));
        }
        extra = math.max(extra, center.dx + painter.width / 2);
        // the labels of a pair are placed first: they have a side to keep
        if (side != 0) {
          edgeLabels.insert(pairLabels++, (painter, center));
        } else {
          edgeLabels.add((painter, center));
        }
      }
    }
    // after every edge, so no later edge is drawn across a label: the line
    // under each label is erased, then the label is written in the gap
    final erase = Paint()..blendMode = BlendMode.clear;
    void clearUnder(Rect gap) {
      ops.add((canvas) => canvas.drawRect(gap, erase));
      if (!boxed) return;
      // the erased bit of any group box under it is painted back
      final under = [
        for (final box in drawOrder.map((g) => boxes[g]).nonNulls)
          if (box.outerRect.overlaps(gap)) box,
      ];
      if (under.isEmpty) return;
      ops.add((canvas) {
        canvas
          ..save()
          ..clipRect(gap);
        for (final box in under) {
          canvas
            ..drawRRect(box, tint)
            ..drawRRect(box, boxLine);
        }
        canvas.restore();
      });
    }

    final taken = <Rect>[];
    for (var (painter, center) in edgeLabels) {
      var gap = Rect.fromCenter(
        center: center,
        width: painter.width + 8,
        height: painter.height + 2,
      );
      // two edges between the same nodes, one each way, put their labels
      // on one spot: a later label moves sideways until it is clear
      for (var tries = 0; tries < 8; tries++) {
        final hit = taken.where((rect) => rect.overlaps(gap)).firstOrNull;
        if (hit == null) break;
        // right up against it, so no bit of line is left between the two
        // (with pairs, away from the label it hits, so a pair's label
        // keeps its side of its line)
        final ahead =
            paired.isEmpty ||
            (horizontal
                ? gap.center.dy >= hit.center.dy
                : gap.center.dx >= hit.center.dx);
        final move = horizontal
            ? Offset(0, ahead ? hit.bottom - gap.top : hit.top - gap.bottom)
            : Offset(ahead ? hit.right - gap.left : hit.left - gap.right, 0);
        gap = gap.shift(move);
        center += move;
      }
      taken.add(gap);
      above = math.min(above, gap.top);
      before = math.min(before, gap.left);
      extra = math.max(extra, gap.right - 4);
      below = math.max(below, gap.bottom - 1);
      clearUnder(gap);
      drawText(painter, center);
    }
    // the group titles last of all, each in a gap cleared like a label's
    for (final (painter, at) in titleSpots) {
      clearUnder(
        Rect.fromLTWH(
          at.dx - 3,
          at.dy - 1,
          painter.width + 6,
          painter.height + 2,
        ),
      );
      ops.add((canvas) => painter.paint(canvas, at));
    }

    for (var i = 0; i < nodes.length; i++) {
      final center = point(middleOf(i), acrossOf[i]);
      final rect = Rect.fromCenter(
        center: center,
        width: sizes[i].width,
        height: sizes[i].height,
      );
      final shape = nodes[i].shape;
      final path = _nodePath(shape, rect);
      if (shape == NodeShape.start) {
        final dot = Paint()..color = text;
        ops.add((canvas) => canvas.drawPath(path, dot));
        continue;
      }
      if (shape == NodeShape.end) {
        final dot = Paint()..color = text;
        final ring = stroke(text, 1.6);
        final inner = rect.deflate(4);
        ops.add(
          (canvas) => canvas
            ..drawOval(rect.deflate(0.8), ring)
            ..drawOval(inner, dot),
        );
        continue;
      }
      // the diagram's own colors (classDef, style) go over the theme's
      final own = nodes[i].style;
      final ownFill = own?.fill;
      final ownStroke = own?.stroke;
      final inside = Paint()..color = ownFill == null ? fill : Color(ownFill);
      final width = own?.strokeWidth ?? 1.4;
      // "stroke-width:0" is no outline at all
      final outline = stroke(
        width <= 0
            ? const Color(0x00000000)
            : ownStroke == null
            ? border
            : Color(ownStroke),
        width,
      );
      final edge = own?.dashed == true ? _dash(path) : path;
      ops.add(
        (canvas) => canvas
          ..drawPath(path, inside)
          ..drawPath(edge, outline),
      );
      final parts = classes[i];
      if (parts == null) {
        drawText(labels[i], center);
      } else {
        _drawClass(parts, rect, outline);
      }
    }

    // notes: a pale folded sheet, joined to its target by a dotted line
    for (var k = 0; k < noteTexts.length; k++) {
      final i = firstNote + k;
      final target = noteTargets[k];
      final box = target < 0 ? boxes[-1 - target]?.outerRect : null;
      Offset from;
      var to = Offset.zero;
      final int toward;
      if (sideways) {
        // a note in a rank of its own: from the target's (or box's) side
        // facing it, level with the note where they overlap
        final sheet = rectOf(i);
        final aim = box ?? rectOf(target);
        final right = sheet.center.dx > aim.center.dx;
        // level where the two overlap; otherwise a slanted line between
        // their middles
        final low = math.max(aim.top, sheet.top) + 4;
        final high = math.min(aim.bottom, sheet.bottom) - 4;
        final level = low <= high;
        final y = level
            ? sheet.center.dy.clamp(low, high).toDouble()
            : aim.center.dy;
        from = Offset(right ? aim.right : aim.left, y);
        to = Offset(
          right ? sheet.left : sheet.right,
          level ? y : sheet.center.dy,
        );
        toward = 0;
      } else if (box != null) {
        // from the side of the box facing the note
        final note = rectOf(i).center;
        final after = horizontal
            ? note.dy > box.center.dy
            : note.dx > box.center.dx;
        toward = after ? 1 : -1;
        from = horizontal
            ? Offset(note.dx, after ? box.bottom : box.top)
            : Offset(after ? box.right : box.left, note.dy);
      } else {
        final node = target < 0 ? i : target;
        toward = acrossOf[i] > acrossOf[node] ? 1 : -1;
        from = point(
          middleOf(node),
          acrossOf[node] + toward * across(sizes[node]) / 2,
        );
      }
      if (!sideways) {
        to = point(middleOf(i), acrossOf[i] - toward * across(sizes[i]) / 2);
      }
      final noteLine =
          look.noteBorderColor ??
          const Color(0xFFC9A227).withValues(alpha: 0.8);
      drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..lineTo(to.dx, to.dy),
        stroke(noteLine, 1),
        dashed: true,
      );
      _drawNote(rectOf(i), noteTexts[k], noteLine);
    }

    final width = (horizontal ? totalAlong : totalAcross) + inset * 2;
    final height = (horizontal ? totalAcross : totalAlong) + inset * 2;
    // a label past the top or left edge moves the whole drawing in
    final inward = Offset(
      before < 0 ? _pad / 2 - before : 0,
      above < 0 ? _pad / 2 - above : 0,
    );
    if (inward != Offset.zero) {
      ops.insert(0, (canvas) => canvas.translate(inward.dx, inward.dy));
    }
    return (
      Size(
        math.max(width + _pad * 2, extra + _pad) + inward.dx,
        math.max(height + _pad * 2, below + _pad) + inward.dy,
      ),
      '${switch (chart.kind) {
        FlowKind.flowchart => 'Flowchart',
        FlowKind.state => 'State diagram',
        FlowKind.classes => 'Class diagram',
        FlowKind.entities => 'ER diagram',
      }}: ${chart.nodes.where((n) => n.label.isNotEmpty).map((n) => n.label.replaceAll('\n', ' ')).join(', ')}',
    );
  }

  // a note: pale yellow, its top right corner folded over
  void _drawNote(Rect rect, TextPainter painter, Color outlineColor) {
    const fold = 8.0;
    final sheet = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right - fold, rect.top)
      ..lineTo(rect.right, rect.top + fold)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    final corner = Path()
      ..moveTo(rect.right - fold, rect.top)
      ..lineTo(rect.right - fold, rect.top + fold)
      ..lineTo(rect.right, rect.top + fold);
    final inside = Paint()
      ..color =
          look.noteColor ?? const Color(0xFFF2C94C).withValues(alpha: 0.22);
    final outline = stroke(outlineColor, 1);
    ops.add(
      (canvas) => canvas
        ..drawPath(sheet, inside)
        ..drawPath(sheet, outline)
        ..drawPath(corner, outline),
    );
    drawText(painter, rect.center);
  }

  // How far the outline is from the node's flat side, [offset] away from
  // the middle of that side: 0 for boxes, more for round and pointed ones.
  double _inset(NodeShape shape, Size size, double offset, bool horizontal) {
    if (offset == 0) return 0;
    final halfAcross = (horizontal ? size.height : size.width) / 2;
    final halfAlong = (horizontal ? size.width : size.height) / 2;
    return switch (shape) {
      NodeShape.diamond => offset / halfAcross * halfAlong,
      NodeShape.circle || NodeShape.start || NodeShape.end =>
        halfAlong -
            math.sqrt(math.max(0, halfAlong * halfAlong - offset * offset)),
      _ => 0,
    };
  }

  Size _nodeSize(NodeShape shape, Size label) => switch (shape) {
    NodeShape.diamond => Size(label.width * 1.5 + 36, label.height * 1.6 + 28),
    NodeShape.circle => Size.square(math.max(label.width, label.height) + 28),
    NodeShape.hexagon => Size(label.width + 52, label.height + 20),
    NodeShape.stadium => Size(label.width + 36, label.height + 18),
    NodeShape.start => const Size.square(16),
    NodeShape.end => const Size.square(20),
    _ => Size(label.width + 28, label.height + 18),
  };

  Path _nodePath(NodeShape shape, Rect rect) {
    switch (shape) {
      case NodeShape.rect || NodeShape.classBox || NodeShape.entity:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
      case NodeShape.rounded:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
      case NodeShape.stadium:
        return Path()..addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
        );
      case NodeShape.circle || NodeShape.start || NodeShape.end:
        return Path()..addOval(rect);
      case NodeShape.diamond:
        return Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
      case NodeShape.hexagon:
        final inset = math.min(14.0, rect.width / 4);
        return Path()
          ..moveTo(rect.left + inset, rect.top)
          ..lineTo(rect.right - inset, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.right - inset, rect.bottom)
          ..lineTo(rect.left + inset, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
    }
  }

  // A class box: its name (with «interface» or the like above it), then its
  // fields, then its methods, each part under a line.
  _ClassParts _classParts(FlowNode node) {
    final small = labelStyle.copyWith(
      fontSize: (labelStyle.fontSize ?? 13) * 0.88,
      color: _textOn(node.style),
    );
    // an entity's attributes are one section
    final entity = node.shape == NodeShape.entity;
    final fields = [
      for (final member in node.members)
        if (entity || !member.contains('(')) member,
    ];
    final methods = [
      for (final member in node.members)
        if (!entity && member.contains('(')) member,
    ];
    TextPainter? list(List<String> members) => members.isEmpty
        ? null
        : measure(
            members.join('\n'),
            style: small,
            align: TextAlign.start,
            maxWidth: 260,
          );
    final parts = _ClassParts(
      annotation: node.annotation == null
          ? null
          : measure('«${node.annotation}»', style: small),
      name: measure(
        node.label,
        style: small.copyWith(
          fontSize: labelStyle.fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      fields: list(fields),
      methods: list(methods),
      sections: entity ? (fields.isEmpty ? 0 : 1) : 2,
    );
    return parts;
  }

  void _drawClass(_ClassParts parts, Rect rect, Paint outline) {
    var y = rect.top + _ClassParts.gap;
    for (final title in [parts.annotation, parts.name].nonNulls) {
      drawText(title, Offset(rect.center.dx, y + title.height / 2));
      y += title.height;
    }
    y += _ClassParts.gap;
    // a section is drawn even when it is empty, as Mermaid does
    for (final section in [parts.fields, parts.methods].take(parts.sections)) {
      final top = y;
      ops.add(
        (canvas) => canvas.drawLine(
          Offset(rect.left, top),
          Offset(rect.right, top),
          outline,
        ),
      );
      y += _ClassParts.gap;
      if (section != null) {
        final at = Offset(rect.left + _ClassParts.gap * 2, y);
        ops.add((canvas) => section.paint(canvas, at));
        y += section.height;
      }
      y += _ClassParts.gap;
    }
  }

  // ---- sequence diagram ---------------------------------------------

  (Size, String) _sequence(SequenceDiagram diagram) {
    final ids = diagram.participants;
    final heads = [for (final id in ids) measure(diagram.labels[id] ?? id)];
    final small = labelStyle.copyWith(
      fontSize: (labelStyle.fontSize ?? 13) * 0.92,
    );
    final texts = <Object, TextPainter>{};
    var spacing = 120.0;
    for (final head in heads) {
      spacing = math.max(spacing, head.width + 44);
    }
    for (final item in diagram.items) {
      switch (item) {
        case SequenceMessage():
          final painter = texts[item] = measure(item.text, style: small);
          final span = (ids.indexOf(item.from) - ids.indexOf(item.to)).abs();
          if (span > 0) {
            spacing = math.max(spacing, (painter.width + 28) / span);
          }
        case SequenceNote():
          texts[item] = measure(item.text, style: small, maxWidth: 160);
        case SequenceDivider():
          texts[item] = measure(
            item.text,
            style: small.copyWith(
              fontStyle: FontStyle.italic,
              color: text.withValues(alpha: 0.7),
            ),
            maxWidth: 400,
          );
      }
    }
    final headHeight = heads.map((p) => p.height).fold(0.0, math.max) + 16;
    final firstX = _pad + (heads.first.width + 24) / 2;
    double x(String id) => firstX + ids.indexOf(id) * spacing;

    var right = x(ids.last) + (heads.last.width + 24) / 2;
    var y = _pad + headHeight + 14;
    final linePaint = stroke(line);
    for (final item in diagram.items) {
      final painter = texts[item]!;
      switch (item) {
        case SequenceMessage():
          final from = x(item.from);
          final to = x(item.to);
          if (from == to) {
            // a message to itself: out, down and back
            final top = y + 6;
            final bottom = top + math.max(painter.height, 16) + 4;
            drawPath(
              Path()
                ..moveTo(from, top)
                ..lineTo(from + 26, top)
                ..lineTo(from + 26, bottom)
                ..lineTo(from, bottom),
              linePaint,
              dashed: item.dashed,
            );
            if (item.head == MessageHead.arrow) {
              drawHead(Offset(from, bottom), math.pi, line);
            }
            drawText(
              painter,
              Offset(from + 34 + painter.width / 2, (top + bottom) / 2),
            );
            right = math.max(right, from + 34 + painter.width);
            y = bottom + 12;
          } else {
            drawText(painter, Offset((from + to) / 2, y + painter.height / 2));
            final lineY = y + painter.height + 5;
            drawPath(
              Path()
                ..moveTo(from, lineY)
                ..lineTo(to, lineY),
              linePaint,
              dashed: item.dashed,
            );
            final tip = Offset(to, lineY);
            final angle = to > from ? 0.0 : math.pi;
            if (item.head == MessageHead.arrow) {
              drawHead(tip, angle, line);
            } else if (item.head == MessageHead.cross) {
              final cross = Path()
                ..moveTo(to - 5, lineY - 5)
                ..lineTo(to + 5, lineY + 5)
                ..moveTo(to - 5, lineY + 5)
                ..lineTo(to + 5, lineY - 5);
              drawPath(cross, linePaint);
            }
            y = lineY + 14;
          }
        case SequenceNote():
          final first = x(item.participants.first);
          final last = x(item.participants.last);
          final width = math.max(
            painter.width + 16,
            item.side == NoteSide.over ? (last - first).abs() + 24 : 0.0,
          );
          final center = switch (item.side) {
            NoteSide.right => first + 10 + width / 2,
            NoteSide.left => first - 10 - width / 2,
            NoteSide.over => (first + last) / 2,
          };
          final rect = Rect.fromCenter(
            center: Offset(center, y + painter.height / 2 + 6),
            width: width,
            height: painter.height + 12,
          );
          final inside = Paint()
            ..color =
                look.noteColor ??
                const Color(0xFFF2C94C).withValues(alpha: 0.22);
          final outline = stroke(
            look.noteBorderColor ??
                const Color(0xFFC9A227).withValues(alpha: 0.8),
            1,
          );
          ops.add(
            (canvas) => canvas
              ..drawRect(rect, inside)
              ..drawRect(rect, outline),
          );
          drawText(painter, rect.center);
          right = math.max(right, rect.right);
          y = rect.bottom + 12;
        case SequenceDivider():
          final lineY = y + painter.height / 2;
          final start = _pad;
          final end = right;
          final gap = painter.width / 2 + 8;
          final mid = (start + end) / 2;
          drawPath(
            Path()
              ..moveTo(start, lineY)
              ..lineTo(mid - gap, lineY)
              ..moveTo(mid + gap, lineY)
              ..lineTo(end, lineY),
            stroke(text.withValues(alpha: 0.3), 1),
            dashed: true,
          );
          drawText(painter, Offset(mid, lineY));
          y += painter.height + 12;
      }
    }
    final bottom = y + 4;

    // lifelines and name boxes go under everything drawn so far
    final under = <void Function(Canvas)>[];
    final life = stroke(text.withValues(alpha: 0.35), 1);
    for (var i = 0; i < ids.length; i++) {
      final center = x(ids[i]);
      final lifeline = _dash(
        Path()
          ..moveTo(center, _pad + headHeight)
          ..lineTo(center, bottom),
      );
      final box = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center, _pad + headHeight / 2),
          width: heads[i].width + 24,
          height: headHeight,
        ),
        const Radius.circular(4),
      );
      final inside = Paint()..color = fill;
      final outline = stroke(border);
      final head = heads[i];
      final at = box.center - Offset(head.width / 2, head.height / 2);
      under.add((canvas) {
        canvas
          ..drawPath(lifeline, life)
          ..drawRRect(box, inside)
          ..drawRRect(box, outline);
        head.paint(canvas, at);
      });
    }
    ops.insertAll(0, under);

    final messages = diagram.items.whereType<SequenceMessage>().length;
    return (
      Size(right + _pad, bottom + _pad),
      'Sequence diagram: ${[for (final id in ids) diagram.labels[id] ?? id].join(', ')}; '
          '$messages messages',
    );
  }

  // ---- pie chart ----------------------------------------------------

  (Size, String) _pie(PieChart pie) {
    const radius = 64.0;
    final total = pie.slices.fold(0.0, (sum, slice) => sum + slice.$2);
    final title = pie.title == null
        ? null
        : measure(
            pie.title!,
            style: labelStyle.copyWith(fontWeight: FontWeight.w600),
            maxWidth: 320,
          );
    final top = _pad + (title == null ? 0 : title.height + 10);
    final center = Offset(_pad + radius, top + radius);
    final legendX = center.dx + radius + 20;

    var angle = -math.pi / 2;
    var legendY = top;
    var right = legendX;
    final parts = <String>[];
    final circle = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < pie.slices.length; i++) {
      final (label, value) = pie.slices[i];
      final colors = look.pieColors;
      final palette = colors == null || colors.isEmpty ? _palette : colors;
      final color = palette[i % palette.length];
      final sweep = value / total * 2 * math.pi;
      final paint = Paint()..color = color;
      final start = angle;
      ops.add(
        (canvas) => pie.slices.length == 1
            ? canvas.drawOval(circle, paint)
            : canvas.drawArc(circle, start, sweep, true, paint),
      );
      angle += sweep;

      final percent = (value / total * 100).round();
      parts.add('$label $percent%');
      final painter = measure('$label ($percent%)', maxWidth: 200)
        ..textAlign = TextAlign.start
        ..layout(maxWidth: 200);
      final swatch = Rect.fromLTWH(legendX, legendY + 3, 11, 11);
      ops.add((canvas) => canvas.drawRect(swatch, paint));
      final at = Offset(legendX + 18, legendY);
      ops.add((canvas) => painter.paint(canvas, at));
      right = math.max(right, at.dx + painter.width);
      legendY += painter.height + 6;
    }
    if (title != null) {
      final at = Offset(_pad, _pad);
      ops.add((canvas) => title.paint(canvas, at));
      right = math.max(right, _pad + title.width);
    }
    return (
      Size(right + _pad, math.max(top + radius * 2, legendY) + _pad),
      'Pie chart${pie.title == null ? '' : ' ${pie.title}'}: ${parts.join(', ')}',
    );
  }

  List<Color> get _colors {
    final colors = look.pieColors;
    return colors == null || colors.isEmpty ? _palette : colors;
  }

  // ---- gantt chart --------------------------------------------------

  (Size, String) _gantt(GanttChart chart) {
    final small = labelStyle.copyWith(
      fontSize: (labelStyle.fontSize ?? 13) * 0.9,
    );
    final bold = small.copyWith(fontWeight: FontWeight.w600);
    final title = chart.title == null
        ? null
        : measure(
            chart.title!,
            style: labelStyle.copyWith(fontWeight: FontWeight.w600),
            maxWidth: 360,
          );
    final palette = _colors;

    // one row per task, under a header row each time the section changes
    final rows = <(TextPainter, GanttTask?)>[];
    String? section;
    for (final task in chart.tasks) {
      if (task.section != null && task.section != section) {
        rows.add((
          measure(
            task.section!,
            style: bold,
            maxWidth: 150,
            align: TextAlign.start,
          ),
          null,
        ));
      }
      section = task.section;
      rows.add((
        measure(task.name, style: small, maxWidth: 150, align: TextAlign.start),
        task,
      ));
    }
    final nameWidth = rows.map((row) => row.$1.width).fold(0.0, math.max);
    final first = chart.tasks
        .map((task) => task.start)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final last = chart.tasks
        .map((task) => task.end)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    double days(DateTime time) =>
        time.difference(first).inMilliseconds / Duration.millisecondsPerDay;
    // a chart of hours gets the width a few days would
    final span = days(last) < 1 ? math.max(days(last), 1 / 24) : days(last);
    final dayWidth = span < 1 ? 300 / span : (300 / span).clamp(3.0, 28.0);
    final left = _pad + nameWidth + 12;
    double x(DateTime time) => left + days(time) * dayWidth;

    final top = _pad + (title == null ? 0 : title.height + 10);
    if (title != null) {
      final at = const Offset(_pad, _pad);
      ops.add((canvas) => title.paint(canvas, at));
    }
    // the grid goes under the bars, once the rows are known
    final gridAt = ops.length;
    var right = math.max(left + span * dayWidth, _pad + (title?.width ?? 0));
    var y = top;
    for (final (painter, task) in rows) {
      final height = math.max(22.0, painter.height + 8);
      final at = Offset(_pad, y + (height - painter.height) / 2);
      ops.add((canvas) => painter.paint(canvas, at));
      if (task != null) {
        final color =
            palette[math.max(0, chart.sections.indexOf(task.section ?? '')) %
                palette.length];
        final alpha = task.done ? 0.35 : (task.active ? 1.0 : 0.7);
        final inside = Paint()..color = color.withValues(alpha: alpha);
        final outline = task.critical
            ? stroke(_palette[3], 2)
            : task.active
            ? stroke(color, 1.5)
            : null;
        Path shape;
        if (task.milestone) {
          // at the middle of its span, as Mermaid draws it
          final center = Offset(
            (x(task.start) + x(task.end)) / 2,
            y + height / 2,
          );
          final r = (height - 8) / 2;
          shape = Path()
            ..moveTo(center.dx, center.dy - r)
            ..lineTo(center.dx + r, center.dy)
            ..lineTo(center.dx, center.dy + r)
            ..lineTo(center.dx - r, center.dy)
            ..close();
          right = math.max(right, center.dx + r);
        } else {
          final start = x(task.start);
          shape = Path()
            ..addRRect(
              RRect.fromLTRBR(
                start,
                y + 4,
                math.max(x(task.end), start + 2),
                y + height - 4,
                const Radius.circular(3),
              ),
            );
        }
        ops.add((canvas) {
          canvas.drawPath(shape, inside);
          if (outline != null) canvas.drawPath(shape, outline);
        });
      }
      y += height;
    }

    // a few dated ticks along the bottom
    const steps = [
      1 / 96,
      1 / 48,
      1 / 24,
      2 / 24,
      3 / 24,
      6 / 24,
      12 / 24,
      1,
      2,
      7,
      14,
      30,
      61,
      91,
      182,
      365,
      730,
    ];
    final step = steps.firstWhere(
      (step) => span / step <= 6,
      orElse: () => steps.last,
    );
    final axisY = y + 4;
    final grid = stroke(text.withValues(alpha: 0.12), 1);
    final under = <void Function(Canvas)>[];
    // the days "excludes" leaves out, as light bands behind everything
    final band = Paint()..color = text.withValues(alpha: 0.07);
    final chartEnd = left + span * dayWidth;
    for (final day in chart.excluded) {
      final from = math.max(x(day), left);
      final to = math.min(x(day.add(const Duration(days: 1))), chartEnd);
      if (to <= from) continue;
      final rect = Rect.fromLTRB(from, top, to, axisY);
      under.add((canvas) => canvas.drawRect(rect, band));
    }
    final sameYear = first.year == last.year;
    var bottom = axisY;
    for (var day = 0.0; day <= span + 1e-6; day += step) {
      final date = first.add(
        Duration(milliseconds: (day * Duration.millisecondsPerDay).round()),
      );
      final tickX = x(date);
      under.add(
        (canvas) =>
            canvas.drawLine(Offset(tickX, top), Offset(tickX, axisY), grid),
      );
      final written = chart.axisFormat == null
          ? null
          : formatGanttDate(date, chart.axisFormat!);
      final painter = measure(
        written ??
            formatGanttDate(
              date,
              step < 1
                  ? '%H:%M'
                  : sameYear
                  ? '%b %e'
                  : '%Y-%m-%d',
            )!,
        style: small.copyWith(color: text.withValues(alpha: 0.7)),
      );
      drawText(painter, Offset(tickX, axisY + 4 + painter.height / 2));
      right = math.max(right, tickX + painter.width / 2);
      bottom = math.max(bottom, axisY + 4 + painter.height);
    }
    final axis = stroke(line, 1);
    under.add(
      (canvas) => canvas.drawLine(
        Offset(left, axisY),
        Offset(left + span * dayWidth, axisY),
        axis,
      ),
    );
    ops.insertAll(gridAt, under);
    return (
      Size(right + _pad, bottom + _pad),
      'Gantt chart${chart.title == null ? '' : ' ${chart.title}'}: '
          '${chart.tasks.map((task) => task.name).join(', ')}',
    );
  }

  // ---- mindmap ------------------------------------------------------

  (Size, String) _mindmap(MindMap map) {
    final palette = _colors;
    final texts = <MindNode, TextPainter>{};
    final sizes = <MindNode, Size>{};
    final columns = <double>[];
    final names = <String>[];
    void size(MindNode node, int depth) {
      names.add(node.text);
      final painter = texts[node] = measure(
        node.text,
        style: depth == 0
            ? labelStyle.copyWith(fontWeight: FontWeight.w600)
            : labelStyle,
        maxWidth: 160,
      );
      final label = painter.size;
      final box = sizes[node] = switch (node.shape) {
        MindShape.circle => Size.square(
          math.max(label.width, label.height) + 24,
        ),
        MindShape.plain when depth > 0 => Size(
          label.width + 12,
          label.height + 10,
        ),
        MindShape.hexagon => Size(label.width + 40, label.height + 16),
        MindShape.bang ||
        MindShape.cloud => Size(label.width + 44, label.height + 30),
        _ => Size(label.width + 24, label.height + 16),
      };
      if (columns.length <= depth) columns.add(0);
      columns[depth] = math.max(columns[depth], box.width);
      for (final child in node.children) {
        size(child, depth + 1);
      }
    }

    size(map.root, 0);
    const columnGap = 48.0;
    final columnX = <double>[_pad];
    for (final width in columns) {
      columnX.add(columnX.last + width + columnGap);
    }

    // each node in its depth's column; a leaf below the one before, a
    // parent level with the middle of its children
    final centers = <MindNode, Offset>{};
    var cursor = _pad;
    double place(MindNode node, int depth) {
      final box = sizes[node]!;
      final start = cursor;
      double y;
      if (node.children.isEmpty) {
        y = cursor + box.height / 2;
      } else {
        final ys = [for (final child in node.children) place(child, depth + 1)];
        y = math.max((ys.first + ys.last) / 2, start + box.height / 2);
      }
      cursor = math.max(cursor, y + box.height / 2 + 10);
      centers[node] = Offset(columnX[depth] + box.width / 2, y);
      return y;
    }

    place(map.root, 0);

    var right = 0.0;
    var bottom = 0.0;
    final shapes = <void Function(Canvas)>[];
    void draw(MindNode node, int depth, Color? color) {
      final center = centers[node]!;
      final box = sizes[node]!;
      final rect = Rect.fromCenter(
        center: center,
        width: box.width,
        height: box.height,
      );
      right = math.max(right, rect.right);
      bottom = math.max(bottom, rect.bottom);
      for (var k = 0; k < node.children.length; k++) {
        final child = node.children[k];
        final branch = color ?? palette[k % palette.length];
        final to = centers[child]!;
        final end = Offset(to.dx - sizes[child]!.width / 2, to.dy);
        final start = Offset(rect.right, center.dy);
        final middle = (start.dx + end.dx) / 2;
        drawPath(
          Path()
            ..moveTo(start.dx, start.dy)
            ..cubicTo(middle, start.dy, middle, end.dy, end.dx, end.dy),
          stroke(branch, depth == 0 ? 2 : 1.4),
        );
        draw(child, depth + 1, branch);
      }
      final inside = Paint()
        ..color = color == null ? fill : color.withValues(alpha: 0.15);
      final outline = stroke(
        color == null ? border : color.withValues(alpha: 0.8),
      );
      final painter = texts[node]!;
      final shape = node.shape == MindShape.plain && depth == 0
          ? MindShape.rounded
          : node.shape;
      final path = switch (shape) {
        MindShape.plain => null,
        MindShape.square => _nodePath(NodeShape.rect, rect),
        MindShape.rounded => _nodePath(NodeShape.rounded, rect),
        MindShape.circle => _nodePath(NodeShape.circle, rect),
        MindShape.hexagon => _nodePath(NodeShape.hexagon, rect),
        MindShape.bang => _bangPath(rect),
        MindShape.cloud => _cloudPath(rect),
      };
      final at = center - Offset(painter.width / 2, painter.height / 2);
      shapes.add((canvas) {
        if (path == null) {
          // a plain topic is its text, underlined
          canvas.drawLine(
            Offset(rect.left, rect.bottom - 1),
            Offset(rect.right, rect.bottom - 1),
            outline,
          );
        } else {
          canvas
            ..drawPath(path, inside)
            ..drawPath(path, outline);
        }
        painter.paint(canvas, at);
      });
    }

    draw(map.root, 0, null);
    // the boxes go over the lines
    ops.addAll(shapes);
    return (
      Size(right + _pad, bottom + _pad),
      'Mindmap: ${names.map((name) => name.replaceAll('\n', ' ')).join(', ')}',
    );
  }

  // a bang: spikes all round, like a burst
  Path _bangPath(Rect rect) {
    const spikes = 14;
    final path = Path();
    for (var k = 0; k < spikes * 2; k++) {
      final angle = k * math.pi / spikes - math.pi / 2;
      final reach = k.isEven ? 1.0 : 0.76;
      final point =
          rect.center +
          Offset(
            math.cos(angle) * rect.width / 2 * reach,
            math.sin(angle) * rect.height / 2 * reach,
          );
      k == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  // a cloud: round bumps all round
  Path _cloudPath(Rect rect) {
    const bumps = 10;
    final points = [
      for (var k = 0; k < bumps; k++)
        rect.center +
            Offset(
              math.cos(2 * math.pi * k / bumps) * rect.width * 0.42,
              math.sin(2 * math.pi * k / bumps) * rect.height * 0.38,
            ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var k = 1; k <= bumps; k++) {
      final from = points[k - 1];
      final to = points[k % bumps];
      path.arcToPoint(to, radius: Radius.circular((to - from).distance * 0.62));
    }
    return path..close();
  }

  // ---- timeline -----------------------------------------------------

  (Size, String) _timeline(Timeline timeline) {
    final palette = _colors;
    final bold = labelStyle.copyWith(fontWeight: FontWeight.w600);
    final small = labelStyle.copyWith(
      fontSize: (labelStyle.fontSize ?? 13) * 0.9,
    );
    final title = timeline.title == null
        ? null
        : measure(timeline.title!, style: bold, maxWidth: 360);
    final periods = timeline.periods;
    final sections = <String>{
      for (final period in periods)
        if (period.section != null) period.section!,
    }.toList();
    final heads = [
      for (final period in periods)
        measure(period.text, style: bold, maxWidth: 140),
    ];
    final events = [
      for (final period in periods)
        [
          for (final event in period.events)
            measure(event, style: small, maxWidth: 140),
        ],
    ];
    const columnGap = 12.0;
    final widths = [
      for (var k = 0; k < periods.length; k++)
        math.max(
          90.0,
          [
                heads[k].width,
                for (final event in events[k]) event.width,
              ].fold(0.0, math.max) +
              20,
        ),
    ];
    final xs = <double>[_pad];
    for (final width in widths) {
      xs.add(xs.last + width + columnGap);
    }
    Color colorOf(int k) =>
        palette[(sections.isEmpty
                ? k
                : math.max(0, sections.indexOf(periods[k].section ?? ''))) %
            palette.length];

    var y = _pad;
    var right = xs.last - columnGap;
    if (title != null) {
      final at = Offset(_pad, y);
      ops.add((canvas) => title.paint(canvas, at));
      right = math.max(right, _pad + title.width);
      y += title.height + 10;
    }
    if (sections.isNotEmpty) {
      // a band over the periods of each section
      var height = 0.0;
      final runs = <(int, int, TextPainter)>[];
      for (var k = 0; k < periods.length;) {
        var end = k;
        while (end + 1 < periods.length &&
            periods[end + 1].section == periods[k].section) {
          end++;
        }
        final name = periods[k].section;
        if (name != null) {
          final painter = measure(
            name,
            style: bold,
            maxWidth: xs[end + 1] - columnGap - xs[k] - 12,
          );
          height = math.max(height, painter.height + 10);
          runs.add((k, end, painter));
        }
        k = end + 1;
      }
      for (final (start, end, painter) in runs) {
        final color = colorOf(start);
        final band = RRect.fromLTRBR(
          xs[start],
          y,
          xs[end + 1] - columnGap,
          y + height,
          const Radius.circular(6),
        );
        final inside = Paint()..color = color.withValues(alpha: 0.3);
        final outline = stroke(color, 1);
        ops.add(
          (canvas) => canvas
            ..drawRRect(band, inside)
            ..drawRRect(band, outline),
        );
        drawText(painter, band.center);
      }
      y += height + 8;
    }
    final headHeight =
        heads.map((head) => head.height).fold(0.0, math.max) + 14;
    final axisY = y + headHeight + 14;
    final axis = stroke(line, 1.4);
    drawPath(
      Path()
        ..moveTo(_pad, axisY)
        ..lineTo(right, axisY),
      axis,
    );
    drawHead(Offset(right, axisY), 0, line);
    var bottom = axisY + 6;
    for (var k = 0; k < periods.length; k++) {
      final color = colorOf(k);
      final middle = xs[k] + widths[k] / 2;
      var eventY = axisY + 14;
      final boxes = <(RRect, TextPainter)>[];
      for (final event in events[k]) {
        final box = RRect.fromLTRBR(
          xs[k],
          eventY,
          xs[k] + widths[k],
          eventY + event.height + 10,
          const Radius.circular(4),
        );
        boxes.add((box, event));
        eventY = box.bottom + 8;
      }
      final lastBox = boxes.lastOrNull;
      if (lastBox != null) {
        // a dotted line down from the period through its events
        drawPath(
          Path()
            ..moveTo(middle, y + headHeight)
            ..lineTo(middle, lastBox.$1.top),
          stroke(color.withValues(alpha: 0.6), 1),
          dashed: true,
        );
        bottom = math.max(bottom, lastBox.$1.bottom);
      }
      final head = RRect.fromLTRBR(
        xs[k],
        y,
        xs[k] + widths[k],
        y + headHeight,
        const Radius.circular(6),
      );
      final headInside = Paint()..color = color.withValues(alpha: 0.2);
      final outline = stroke(color);
      final eventInside = Paint()..color = color.withValues(alpha: 0.08);
      final eventOutline = stroke(color.withValues(alpha: 0.5), 1);
      final dot = Paint()..color = color;
      ops.add((canvas) {
        canvas
          ..drawRRect(head, headInside)
          ..drawRRect(head, outline)
          ..drawCircle(Offset(middle, axisY), 4, dot);
        for (final (box, _) in boxes) {
          canvas
            ..drawRRect(box, eventInside)
            ..drawRRect(box, eventOutline);
        }
      });
      drawText(heads[k], head.center);
      for (final (box, event) in boxes) {
        drawText(event, box.center);
      }
    }
    return (
      Size(right + _pad, bottom + _pad),
      'Timeline${timeline.title == null ? '' : ' ${timeline.title}'}: '
          '${[for (final period in periods) period.events.isEmpty ? period.text : '${period.text}: ${period.events.join(', ')}'].join('; ')}',
    );
  }

  // ---- shared by the charts below -----------------------------------

  TextStyle get _small =>
      labelStyle.copyWith(fontSize: (labelStyle.fontSize ?? 13) * 0.88);

  TextPainter? _titleOf(String? title) => title == null
      ? null
      : measure(
          title,
          style: labelStyle.copyWith(fontWeight: FontWeight.w600),
          maxWidth: 360,
        );

  // text read from the bottom up, as along a y axis
  void drawTextTurned(TextPainter painter, Offset center) {
    final at = Offset(-painter.width / 2, -painter.height / 2);
    ops.add((canvas) {
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(-math.pi / 2);
      painter.paint(canvas, at);
      canvas.restore();
    });
  }

  // ---- git graph ----------------------------------------------------

  (Size, String) _gitGraph(GitGraph graph) {
    final palette = _colors;
    final small = _small;
    final bold = small.copyWith(fontWeight: FontWeight.w600);
    final commits = graph.commits;
    // a branch gets a lane once it has a commit
    final used = [
      for (var b = 0; b < graph.branches.length; b++)
        if (commits.any((commit) => commit.branch == b)) b,
    ];
    final laneOf = {for (var k = 0; k < used.length; k++) used[k]: k};
    final names = [
      for (final b in used)
        measure(graph.branches[b], style: bold, maxWidth: 120),
    ];
    final ids = [
      for (final commit in commits)
        commit.label == null
            ? null
            : measure(commit.label!, style: small, maxWidth: 90),
    ];
    final tags = [
      for (final commit in commits)
        commit.tag == null
            ? null
            : measure(commit.tag!, style: small, maxWidth: 110),
    ];
    const radius = 8.0;
    final nameWidth = names.map((name) => name.width).fold(0.0, math.max) + 16;
    final tagHeight = tags.nonNulls
        .map((tag) => tag.height)
        .fold(0.0, math.max);
    final tagRoom = tagHeight == 0 ? 0.0 : tagHeight + 10;
    final idRoom = ids.nonNulls.map((id) => id.height).fold(0.0, math.max);
    final laneHeight = math.max(
      tagRoom + radius * 2 + idRoom + 14,
      names.map((name) => name.height).fold(0.0, math.max) + 14,
    );
    // a column per commit, in the order they were made
    final xs = <double>[];
    var right = _pad + nameWidth + 12;
    for (var i = 0; i < commits.length; i++) {
      final width = [
        38.0,
        (ids[i]?.width ?? 0) + 10,
        (tags[i]?.width ?? 0) + 18,
      ].reduce(math.max);
      xs.add(right + width / 2);
      right += width;
    }
    double laneY(int lane) => _pad + lane * laneHeight + tagRoom + radius + 2;
    Offset at(int i) => Offset(xs[i], laneY(laneOf[commits[i].branch]!));
    Color colorOf(int branch) => palette[laneOf[branch]! % palette.length];

    for (var k = 0; k < used.length; k++) {
      final color = palette[k % palette.length];
      final y = laneY(k);
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          _pad,
          y - names[k].height / 2 - 4,
          nameWidth,
          names[k].height + 8,
        ),
        const Radius.circular(6),
      );
      final inside = Paint()..color = color.withValues(alpha: 0.2);
      final outline = stroke(color, 1);
      final lane = stroke(color.withValues(alpha: 0.35), 1);
      final end = Offset(right, y);
      ops.add(
        (canvas) => canvas
          ..drawLine(Offset(box.right, y), end, lane)
          ..drawRRect(box, inside)
          ..drawRRect(box, outline),
      );
      drawText(names[k], box.center);
    }
    // the lines between commits: straight along a lane, an S where a
    // branch leaves a lane or is merged into one
    for (var i = 0; i < commits.length; i++) {
      final commit = commits[i];
      final to = at(i);
      for (var p = 0; p < commit.parents.length; p++) {
        final parent = commit.parents[p];
        final from = at(parent);
        final middle = (from.dx + to.dx) / 2;
        final path = Path()..moveTo(from.dx, from.dy);
        if (from.dy == to.dy) {
          path.lineTo(to.dx, to.dy);
        } else {
          path.cubicTo(middle, from.dy, middle, to.dy, to.dx, to.dy);
        }
        // a merge line has the color of the branch merged in
        drawPath(
          path,
          stroke(colorOf(p == 0 ? commit.branch : commits[parent].branch), 2),
        );
      }
    }
    final erase = Paint()..blendMode = BlendMode.clear;
    final tagInside = Paint()
      ..color =
          look.noteColor ?? const Color(0xFFF2C94C).withValues(alpha: 0.22);
    final tagOutline = stroke(
      look.noteBorderColor ?? const Color(0xFFC9A227).withValues(alpha: 0.8),
      1,
    );
    for (var i = 0; i < commits.length; i++) {
      final commit = commits[i];
      final center = at(i);
      final color = colorOf(commit.branch);
      final solid = Paint()..color = color;
      final pen = stroke(color, 2.4);
      switch (commit.type) {
        case GitCommitType.highlight:
          // a square
          final square = Rect.fromCircle(center: center, radius: radius);
          ops.add((canvas) => canvas.drawRect(square, solid));
        case GitCommitType.reverse:
          // a ring with a cross in it
          const arm = radius * 0.45;
          final cross = Path()
            ..moveTo(center.dx - arm, center.dy - arm)
            ..lineTo(center.dx + arm, center.dy + arm)
            ..moveTo(center.dx + arm, center.dy - arm)
            ..lineTo(center.dx - arm, center.dy + arm);
          ops.add(
            (canvas) => canvas
              ..drawCircle(center, radius, erase)
              ..drawCircle(center, radius - 1.2, pen)
              ..drawPath(cross, pen),
          );
        case GitCommitType.normal when commit.merge:
          // a ring around a dot
          ops.add(
            (canvas) => canvas
              ..drawCircle(center, radius, erase)
              ..drawCircle(center, radius - 1.2, pen)
              ..drawCircle(center, 2.6, solid),
          );
        case GitCommitType.normal:
          ops.add((canvas) => canvas.drawCircle(center, radius, solid));
      }
      final tag = tags[i];
      if (tag != null) {
        final box = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(
              center.dx,
              center.dy - radius - 5 - (tag.height + 4) / 2,
            ),
            width: tag.width + 10,
            height: tag.height + 4,
          ),
          const Radius.circular(3),
        );
        ops.add(
          (canvas) => canvas
            ..drawRRect(box, tagInside)
            ..drawRRect(box, tagOutline),
        );
        drawText(tag, box.center);
      }
      final id = ids[i];
      if (id != null) {
        drawText(id, Offset(center.dx, center.dy + radius + 3 + id.height / 2));
      }
    }
    return (
      Size(right + _pad, _pad * 2 + used.length * laneHeight),
      'Git graph: ${[for (final b in used) graph.branches[b]].join(', ')}; '
          '${commits.length} commits',
    );
  }

  // ---- user journey -------------------------------------------------

  (Size, String) _journey(Journey journey) {
    final palette = _colors;
    final small = _small;
    final bold = labelStyle.copyWith(fontWeight: FontWeight.w600);
    final title = _titleOf(journey.title);
    final tasks = journey.tasks;
    final sections = <String>{
      for (final task in tasks)
        if (task.section != null) task.section!,
    }.toList();
    final actors = <String>{for (final task in tasks) ...task.actors}.toList();
    final names = [
      for (final task in tasks) measure(task.name, style: small, maxWidth: 110),
    ];
    const columnGap = 10.0;
    final widths = [for (final name in names) math.max(84.0, name.width + 16)];
    final xs = <double>[_pad];
    for (final width in widths) {
      xs.add(xs.last + width + columnGap);
    }
    Color colorOf(int k) =>
        palette[math.max(0, sections.indexOf(tasks[k].section ?? '')) %
            palette.length];
    // actors are told apart by colors from the far end of the palette
    Color actorColor(String actor) =>
        palette[(palette.length - 1 - actors.indexOf(actor)) % palette.length];

    var y = _pad;
    var right = xs.last - columnGap;
    if (title != null) {
      final at = Offset(_pad, y);
      ops.add((canvas) => title.paint(canvas, at));
      right = math.max(right, _pad + title.width);
      y += title.height + 10;
    }
    if (actors.isNotEmpty) {
      // who is who: a dot and a name each
      var x = _pad;
      var height = 0.0;
      for (final actor in actors) {
        final painter = measure(actor, style: small, maxWidth: 120);
        final dot = Paint()..color = actorColor(actor);
        final center = Offset(x + 5, y + painter.height / 2);
        final at = Offset(x + 14, y);
        ops.add((canvas) {
          canvas.drawCircle(center, 4, dot);
          painter.paint(canvas, at);
        });
        x = at.dx + painter.width + 14;
        height = math.max(height, painter.height);
      }
      right = math.max(right, x - 14);
      y += height + 10;
    }
    if (sections.isNotEmpty) {
      // a band over the tasks of each section
      var height = 0.0;
      final runs = <(int, int, TextPainter)>[];
      for (var k = 0; k < tasks.length;) {
        var end = k;
        while (end + 1 < tasks.length &&
            tasks[end + 1].section == tasks[k].section) {
          end++;
        }
        final name = tasks[k].section;
        if (name != null) {
          final painter = measure(
            name,
            style: bold,
            maxWidth: xs[end + 1] - columnGap - xs[k] - 12,
          );
          height = math.max(height, painter.height + 10);
          runs.add((k, end, painter));
        }
        k = end + 1;
      }
      for (final (start, end, painter) in runs) {
        final color = colorOf(start);
        final band = RRect.fromLTRBR(
          xs[start],
          y,
          xs[end + 1] - columnGap,
          y + height,
          const Radius.circular(6),
        );
        final inside = Paint()..color = color.withValues(alpha: 0.3);
        final outline = stroke(color, 1);
        ops.add(
          (canvas) => canvas
            ..drawRRect(band, inside)
            ..drawRRect(band, outline),
        );
        drawText(painter, band.center);
      }
      y += height + 8;
    }
    final dotRoom = actors.isEmpty ? 0.0 : 12.0;
    final boxHeight =
        names.map((name) => name.height).fold(0.0, math.max) + 12 + dotRoom;
    // under each task a face, higher the better the score
    const faceRadius = 10.0;
    const step = 15.0;
    final faceTop = y + boxHeight + 12;
    final axisY = faceTop + faceRadius * 2 + step * 4 + 8;
    final pen = stroke(line, 1.3);
    final ink = Paint()..color = line;
    for (var k = 0; k < tasks.length; k++) {
      final task = tasks[k];
      final color = colorOf(k);
      final middle = xs[k] + widths[k] / 2;
      final box = RRect.fromLTRBR(
        xs[k],
        y,
        xs[k] + widths[k],
        y + boxHeight,
        const Radius.circular(6),
      );
      final inside = Paint()..color = color.withValues(alpha: 0.2);
      final outline = stroke(color);
      ops.add(
        (canvas) => canvas
          ..drawRRect(box, inside)
          ..drawRRect(box, outline),
      );
      drawText(names[k], Offset(middle, box.top + (boxHeight - dotRoom) / 2));
      for (var a = 0; a < task.actors.length; a++) {
        final dot = Paint()..color = actorColor(task.actors[a]);
        final center = Offset(
          middle + (a - (task.actors.length - 1) / 2) * 11,
          box.bottom - 8,
        );
        ops.add((canvas) => canvas.drawCircle(center, 3.5, dot));
      }
      final face = Offset(
        middle,
        faceTop + faceRadius + (5 - task.score) * step,
      );
      drawPath(
        Path()
          ..moveTo(middle, box.bottom)
          ..lineTo(middle, face.dy - faceRadius),
        stroke(color.withValues(alpha: 0.6), 1),
        dashed: true,
      );
      drawPath(
        Path()
          ..moveTo(middle, face.dy + faceRadius)
          ..lineTo(middle, axisY),
        stroke(color.withValues(alpha: 0.6), 1),
        dashed: true,
      );
      // the mouth bends up for a good score and down for a bad one
      final bend = (task.score - 3) * 2.4;
      final mouthY = face.dy + 4 - bend / 2;
      final mouth = Path()
        ..moveTo(face.dx - 4.5, mouthY)
        ..quadraticBezierTo(face.dx, mouthY + bend, face.dx + 4.5, mouthY);
      final skin = Paint()..color = color.withValues(alpha: 0.25);
      ops.add(
        (canvas) => canvas
          ..drawCircle(face, faceRadius, skin)
          ..drawCircle(face, faceRadius, pen)
          ..drawCircle(face + const Offset(-3.5, -3), 1.2, ink)
          ..drawCircle(face + const Offset(3.5, -3), 1.2, ink)
          ..drawPath(mouth, pen),
      );
      final score = measure('${task.score}', style: small);
      drawText(
        score,
        Offset(face.dx + faceRadius + 4 + score.width / 2, face.dy),
      );
    }
    drawPath(
      Path()
        ..moveTo(_pad, axisY)
        ..lineTo(right, axisY),
      stroke(line, 1.4),
    );
    drawHead(Offset(right, axisY), 0, line);
    return (
      Size(right + _pad, axisY + 6 + _pad),
      'Journey${journey.title == null ? '' : ' ${journey.title}'}: '
          '${[for (final task in tasks) '${task.name} ${task.score}'].join(', ')}',
    );
  }

  // ---- quadrant chart -----------------------------------------------

  (Size, String) _quadrant(QuadrantChart chart) {
    final palette = _colors;
    final small = _small;
    const side = 280.0;
    const half = side / 2;
    final title = _titleOf(chart.title);
    TextPainter? axis(String? text) =>
        text == null ? null : measure(text, style: small, maxWidth: half - 8);
    final xLow = axis(chart.xLow);
    final xHigh = axis(chart.xHigh);
    final yLow = axis(chart.yLow);
    final yHigh = axis(chart.yHigh);
    final yRoom = [
      yLow,
      yHigh,
    ].nonNulls.map((label) => label.height + 6).fold(0.0, math.max);
    final xRoom = [
      xLow,
      xHigh,
    ].nonNulls.map((label) => label.height + 6).fold(0.0, math.max);
    var top = _pad;
    var right = _pad + yRoom + side;
    if (title != null) {
      final at = Offset(_pad, top);
      ops.add((canvas) => title.paint(canvas, at));
      right = math.max(right, _pad + title.width);
      top += title.height + 10;
    }
    final plot = Rect.fromLTWH(_pad + yRoom, top, side, side);
    // quadrant-1 is the top right one, then they go round to the left
    final corners = [
      Offset(plot.center.dx, plot.top),
      plot.topLeft,
      Offset(plot.left, plot.center.dy),
      plot.center,
    ];
    final nameStyle = small.copyWith(
      fontWeight: FontWeight.w600,
      color: text.withValues(alpha: 0.75),
    );
    for (var q = 0; q < 4; q++) {
      final rect = corners[q] & const Size(half, half);
      // the two diagonals in two strengths, so the four are told apart
      final inside = Paint()
        ..color = fill.withValues(alpha: fill.a * (q.isEven ? 1 : 0.4));
      ops.add((canvas) => canvas.drawRect(rect, inside));
      final name = chart.quadrants[q];
      if (name == null) continue;
      final painter = measure(name, style: nameStyle, maxWidth: half - 12);
      drawText(
        painter,
        Offset(rect.center.dx, rect.top + 8 + painter.height / 2),
      );
    }
    final frame = stroke(border, 1);
    final cross = Path()
      ..moveTo(plot.center.dx, plot.top)
      ..lineTo(plot.center.dx, plot.bottom)
      ..moveTo(plot.left, plot.center.dy)
      ..lineTo(plot.right, plot.center.dy);
    ops.add(
      (canvas) => canvas
        ..drawPath(cross, frame)
        ..drawRect(plot, frame),
    );
    for (var i = 0; i < chart.points.length; i++) {
      final point = chart.points[i];
      final center = Offset(
        plot.left + point.x * side,
        plot.bottom - point.y * side,
      );
      final dot = Paint()..color = palette[i % palette.length];
      ops.add((canvas) => canvas.drawCircle(center, 4.5, dot));
      final label = measure(point.name, style: small, maxWidth: 100);
      // under the dot, or over it at the bottom edge; kept inside the plot
      final under = center.dy + 7 + label.height <= plot.bottom;
      drawText(
        label,
        Offset(
          center.dx.clamp(
            plot.left + label.width / 2,
            plot.right - label.width / 2,
          ),
          under
              ? center.dy + 7 + label.height / 2
              : center.dy - 7 - label.height / 2,
        ),
      );
    }
    // the axis names: "low" by the first half, "high" by the second; one
    // name alone is centered
    void along(
      TextPainter? low,
      TextPainter? high,
      Offset Function(double) at,
      void Function(TextPainter, Offset) draw,
    ) {
      if (low != null) draw(low, at(high == null ? half : half / 2));
      if (high != null) draw(high, at(half * 1.5));
    }

    along(
      xLow,
      xHigh,
      (x) => Offset(plot.left + x, plot.bottom + xRoom / 2),
      drawText,
    );
    along(
      yLow,
      yHigh,
      (y) => Offset(plot.left - yRoom / 2, plot.bottom - y),
      drawTextTurned,
    );
    final names = chart.points.isEmpty
        ? chart.quadrants.nonNulls
        : chart.points.map((point) => point.name);
    return (
      Size(right + _pad, plot.bottom + xRoom + _pad),
      'Quadrant chart${chart.title == null ? '' : ' ${chart.title}'}: '
          '${names.join(', ')}',
    );
  }

  // ---- sankey diagram -----------------------------------------------

  (Size, String) _sankey(Sankey sankey) {
    final palette = _colors;
    final count = sankey.nodes.length;
    final links = sankey.links;
    // links that close a cycle don't push columns to the right
    final back = <int>{};
    final state = List.filled(count, 0);
    void visit(int node) {
      state[node] = 1;
      for (var i = 0; i < links.length; i++) {
        if (links[i].source != node) continue;
        final next = links[i].target;
        if (state[next] == 1) {
          back.add(i);
        } else if (state[next] == 0) {
          visit(next);
        }
      }
      state[node] = 2;
    }

    for (var i = 0; i < count; i++) {
      if (state[i] == 0) visit(i);
    }
    final column = List.filled(count, 0);
    for (var round = 0; round < count; round++) {
      var moved = false;
      for (var i = 0; i < links.length; i++) {
        if (back.contains(i)) continue;
        final link = links[i];
        if (column[link.target] < column[link.source] + 1) {
          column[link.target] = column[link.source] + 1;
          moved = true;
        }
      }
      if (!moved) break;
    }
    final into = List.filled(count, 0.0);
    final outOf = List.filled(count, 0.0);
    for (final link in links) {
      outOf[link.source] += link.value;
      into[link.target] += link.value;
    }
    final values = [
      for (var i = 0; i < count; i++) math.max(into[i], outOf[i]),
    ];
    final labels = [
      for (var i = 0; i < count; i++)
        measure(
          '${sankey.nodes[i]} ${_plain(values[i])}',
          style: _small,
          maxWidth: 140,
          align: TextAlign.start,
        ),
    ];
    final columns = [
      for (var c = 0; c <= column.fold(0, math.max); c++)
        [
          for (var i = 0; i < count; i++)
            if (column[i] == c) i,
        ],
    ];
    const barWidth = 12.0;
    const nodeGap = 8.0;
    final columnGap = math.max(
      80.0,
      labels.map((label) => label.width).fold(0.0, math.max) + 24,
    );
    // one scale for every column: the fullest one fills the height
    final height = math.max(
      200.0,
      columns.map((nodes) => nodes.length).fold(0, math.max) * 26.0,
    );
    final scale = columns
        .map(
          (nodes) =>
              (height - (nodes.length - 1) * nodeGap) /
              nodes.fold(0.0, (sum, i) => sum + values[i]),
        )
        .reduce(math.min);
    final bars = List.filled(count, Rect.zero);
    var bottom = _pad;
    var right = _pad;
    for (var c = 0; c < columns.length; c++) {
      final x = _pad + c * (barWidth + columnGap);
      var y = _pad;
      for (final i in columns[c]) {
        final bar = math.max(2.0, values[i] * scale);
        // a thin bar still gets the room its label needs
        final slot = math.max(bar, labels[i].height);
        bars[i] = Rect.fromLTWH(x, y + (slot - bar) / 2, barWidth, bar);
        y += slot + nodeGap;
        right = math.max(right, x + barWidth + 6 + labels[i].width);
      }
      bottom = math.max(bottom, y - nodeGap);
    }
    // each link is a band as thick as its value, from its place on the
    // source's right side to its place on the target's left side
    final left = List.filled(count, 0.0);
    final leaving = List.filled(count, 0.0);
    for (final link in links) {
      final from = bars[link.source];
      final to = bars[link.target];
      final thick = math.max(1.0, link.value * scale);
      final y0 = from.top + leaving[link.source];
      final y1 = to.top + left[link.target];
      leaving[link.source] += link.value * scale;
      left[link.target] += link.value * scale;
      final middle = (from.right + to.left) / 2;
      final band = Path()
        ..moveTo(from.right, y0)
        ..cubicTo(middle, y0, middle, y1, to.left, y1)
        ..lineTo(to.left, y1 + thick)
        ..cubicTo(
          middle,
          y1 + thick,
          middle,
          y0 + thick,
          from.right,
          y0 + thick,
        )
        ..close();
      final paint = Paint()
        ..color = palette[link.source % palette.length].withValues(alpha: 0.35);
      ops.add((canvas) => canvas.drawPath(band, paint));
    }
    for (var i = 0; i < count; i++) {
      final bar = bars[i];
      final paint = Paint()..color = palette[i % palette.length];
      final label = labels[i];
      final at = Offset(bar.right + 6, bar.center.dy - label.height / 2);
      ops.add((canvas) {
        canvas.drawRect(bar, paint);
        label.paint(canvas, at);
      });
    }
    return (
      Size(right + _pad, bottom + _pad),
      'Sankey diagram: ${[for (final link in links) '${sankey.nodes[link.source]} to ${sankey.nodes[link.target]} ${_plain(link.value)}'].join(', ')}',
    );
  }

  // ---- xy chart -----------------------------------------------------

  (Size, String) _xyChart(XyChart chart) {
    final palette = _colors;
    final small = _small;
    final title = _titleOf(chart.title);
    final categories = chart.categories;
    final count =
        categories?.length ??
        chart.series
            .map((series) => series.values.length)
            .fold<int>(0, math.max);
    final xRange = chart.xRange;
    final names = [
      for (var k = 0; k < count; k++)
        measure(
          categories != null
              ? categories[k]
              : xRange == null
              ? '${k + 1}'
              : _plain(
                  count == 1
                      ? xRange.$1
                      : xRange.$1 + (xRange.$2 - xRange.$1) * k / (count - 1),
                ),
          style: small,
          maxWidth: 70,
        ),
    ];
    final all = [
      for (final series in chart.series) ...series.values.take(count),
    ];
    var low = chart.yRange?.$1 ?? all.fold<double>(0, math.min);
    var high = chart.yRange?.$2 ?? all.fold<double>(low, math.max);
    if (high <= low) high = low + 1;
    const plotHeight = 170.0;
    const steps = 4;
    final ticks = [
      for (var k = 0; k <= steps; k++)
        measure(_plain(low + (high - low) * k / steps), style: small),
    ];
    final xTitle = chart.xTitle == null
        ? null
        : measure(chart.xTitle!, style: small, maxWidth: 200);
    final yTitle = chart.yTitle == null
        ? null
        : measure(chart.yTitle!, style: small, maxWidth: plotHeight);
    final band = [
      36.0,
      220 / count,
      names.map((name) => name.width).fold(0.0, math.max) + 10,
    ].reduce(math.max);
    var top = _pad;
    final left =
        _pad +
        (yTitle == null ? 0 : yTitle.height + 6) +
        ticks.map((tick) => tick.width).fold(0.0, math.max) +
        6;
    var right = left + band * count;
    if (title != null) {
      final at = Offset(_pad, top);
      ops.add((canvas) => title.paint(canvas, at));
      right = math.max(right, _pad + title.width);
      top += title.height + 10;
    }
    // room for the top tick's text
    top += ticks.last.height / 2;
    final bottom = top + plotHeight;
    final plotRight = left + band * count;
    double yOf(double value) =>
        bottom - (value.clamp(low, high) - low) / (high - low) * plotHeight;

    final grid = stroke(line.withValues(alpha: line.a * 0.3), 1);
    for (var k = 0; k <= steps; k++) {
      final y = bottom - plotHeight * k / steps;
      final tick = ticks[k];
      if (k > 0) {
        ops.add(
          (canvas) =>
              canvas.drawLine(Offset(left, y), Offset(plotRight, y), grid),
        );
      }
      drawText(tick, Offset(left - 6 - tick.width / 2, y));
    }
    // bars stand side by side in their category, on the zero line (or on
    // the bottom when zero is out of range)
    final barSeries = [
      for (var s = 0; s < chart.series.length; s++)
        if (chart.series[s].bar) s,
    ];
    final base = yOf(0);
    for (var b = 0; b < barSeries.length; b++) {
      final series = chart.series[barSeries[b]];
      final paint = Paint()..color = palette[barSeries[b] % palette.length];
      final width = band * 0.7 / barSeries.length;
      for (var k = 0; k < series.values.length && k < count; k++) {
        final x = left + k * band + band * 0.15 + b * width;
        final y = yOf(series.values[k]);
        final bar = Rect.fromLTRB(
          x,
          math.min(y, base),
          x + width,
          math.max(y, base),
        );
        ops.add((canvas) => canvas.drawRect(bar, paint));
      }
    }
    final axes = stroke(line, 1);
    final frame = Path()
      ..moveTo(left, top)
      ..lineTo(left, bottom)
      ..lineTo(plotRight, bottom);
    ops.add((canvas) => canvas.drawPath(frame, axes));
    // lines go over the bars, through the middle of each category
    for (var s = 0; s < chart.series.length; s++) {
      final series = chart.series[s];
      if (series.bar) continue;
      final color = palette[s % palette.length];
      final points = [
        for (var k = 0; k < series.values.length && k < count; k++)
          Offset(left + k * band + band / 2, yOf(series.values[k])),
      ];
      if (points.isEmpty) continue;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final pen = stroke(color, 2);
      final dot = Paint()..color = color;
      ops.add((canvas) {
        canvas.drawPath(path, pen);
        for (final point in points) {
          canvas.drawCircle(point, 3, dot);
        }
      });
    }
    var below = bottom + 4;
    for (var k = 0; k < count; k++) {
      drawText(
        names[k],
        Offset(left + k * band + band / 2, bottom + 4 + names[k].height / 2),
      );
      below = math.max(below, bottom + 4 + names[k].height);
    }
    if (xTitle != null) {
      drawText(
        xTitle,
        Offset((left + plotRight) / 2, below + 4 + xTitle.height / 2),
      );
      below += 4 + xTitle.height;
      right = math.max(right, (left + plotRight) / 2 + xTitle.width / 2);
    }
    if (yTitle != null) {
      drawTextTurned(
        yTitle,
        Offset(_pad + yTitle.height / 2, top + plotHeight / 2),
      );
    }
    return (
      Size(right + _pad, below + _pad),
      'XY chart${chart.title == null ? '' : ' ${chart.title}'}: '
          '${[for (final series in chart.series) '${series.bar ? 'bar' : 'line'} ${series.values.take(count).map(_plain).join(', ')}'].join('; ')}',
    );
  }
}

// a number as short as it can be written: no ".0", at most two decimals
String _plain(double value) {
  final text = value.toStringAsFixed(2);
  return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
}

Path _dash(Path source, {double on = 5, double off = 4}) {
  final dashed = Path();
  for (final ui.PathMetric metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      dashed.addPath(
        metric.extractPath(distance, math.min(distance + on, metric.length)),
        Offset.zero,
      );
      distance += on + off;
    }
  }
  return dashed;
}

class _ClassParts {
  _ClassParts({
    required this.annotation,
    required this.name,
    required this.fields,
    required this.methods,
    this.sections = 2,
  });

  static const double gap = 6;

  // how many sections are drawn under the name: fields and methods for a
  // class, attributes (if any) for an entity
  final int sections;

  final TextPainter? annotation;
  final TextPainter name;
  final TextPainter? fields;
  final TextPainter? methods;

  Size get size {
    final width = [
      annotation?.width ?? 0,
      name.width,
      (fields?.width ?? 0) + gap * 2,
      (methods?.width ?? 0) + gap * 2,
    ].fold(0.0, math.max);
    final height =
        (annotation?.height ?? 0) +
        name.height +
        (fields?.height ?? 0) +
        (methods?.height ?? 0) +
        gap * (2 + sections * 2);
    return Size(math.max(width + gap * 4, 80), height);
  }
}
