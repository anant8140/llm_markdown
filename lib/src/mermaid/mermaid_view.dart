import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../direction.dart';
import '../style.dart';
import 'mermaid_model.dart';

/// Draws a Mermaid flowchart, sequence diagram or pie chart.
///
/// `StreamingMarkdown` uses it for ` ```mermaid ` code blocks. Other kinds
/// of Mermaid diagram (class, state, gantt, ...) are not drawn: [supports]
/// is false for them and [fallback] is shown.
///
/// In flowcharts, `subgraph` boxes and styling (`classDef`, `style`) are
/// left out; the nodes and edges inside are still drawn.
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

  TextPainter measure(String label, {TextStyle? style, double maxWidth = 220}) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style ?? labelStyle),
      textAlign: TextAlign.center,
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

  _Scene build(MermaidData data) {
    final (size, description) = switch (data) {
      FlowChart() => _flow(data),
      SequenceDiagram() => _sequence(data),
      PieChart() => _pie(data),
    };
    return _Scene(size, ops, painters, description);
  }

  // ---- flowchart ----------------------------------------------------

  (Size, String) _flow(FlowChart chart) {
    final nodes = chart.nodes;
    final index = {for (var i = 0; i < nodes.length; i++) nodes[i].id: i};
    final edges = [
      for (final edge in chart.edges)
        if (edge.from != edge.to) (index[edge.from]!, index[edge.to]!, edge),
    ];

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
    final rankCount = rank.fold(0, math.max) + 1;

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
        segments.add((route.last, layoutRank.length - 1));
        route.add(layoutRank.length - 1);
      }
      segments.add((route.last, high));
      route.add(high);
      routes.add(route);
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

    rows.forEach(place);
    void sweep(Iterable<int> order, int step) {
      for (final r in order) {
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
          wanted[node] = near.isEmpty
              ? position[node]
              : near.reduce((a, b) => a + b) / near.length;
        }
        row.sort((a, b) {
          final byWanted = wanted[a]!.compareTo(wanted[b]!);
          return byWanted != 0 ? byWanted : a.compareTo(b);
        });
        place(row);
      }
    }

    for (var i = 0; i < 2; i++) {
      sweep(Iterable.generate(rankCount - 1, (r) => r + 1), -1);
      sweep(Iterable.generate(rankCount - 1, (r) => rankCount - 2 - r), 1);
    }

    final labels = [for (final node in nodes) measure(node.label)];
    const lane = Size(14, 14);
    final sizes = [
      for (var i = 0; i < count; i++)
        i < nodes.length ? _nodeSize(nodes[i].shape, labels[i].size) : lane,
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
    const rankGap = 44.0;
    const nodeGap = 28.0;

    final rankStart = <double>[];
    final rankSize = <double>[];
    var cursor = 0.0;
    for (final row in rows) {
      final thickness = row
          .where((i) => i < nodes.length)
          .map((i) => along(sizes[i]))
          .fold(0.0, math.max);
      rankStart.add(cursor);
      rankSize.add(thickness);
      cursor += thickness + rankGap;
    }
    final totalAlong = cursor - rankGap;
    final rowWidths = [
      for (final row in rows)
        row.map((i) => across(sizes[i])).fold(0.0, (a, b) => a + b) +
            nodeGap * math.max(0, row.length - 1),
    ];
    final totalAcross = rowWidths.fold(0.0, math.max);

    // from (along, across) to the canvas
    Offset point(double a, double c) {
      final placed = flipped ? totalAlong - a : a;
      return horizontal
          ? Offset(placed + _pad, c + _pad)
          : Offset(c + _pad, placed + _pad);
    }

    final acrossOf = List.filled(count, 0.0);
    for (var r = 0; r < rows.length; r++) {
      var at = (totalAcross - rowWidths[r]) / 2;
      for (final i in rows[r]) {
        acrossOf[i] = at + across(sizes[i]) / 2;
        at += across(sizes[i]) + nodeGap;
      }
    }
    double middleOf(int node) =>
        rankStart[layoutRank[node]] + rankSize[layoutRank[node]] / 2;

    // room for edge labels drawn beside the lines
    var extra = 0.0;
    final edgeLabels = <(TextPainter, Offset)>[];
    final edgePaint = stroke(line);
    for (var i = 0; i < edges.length; i++) {
      final edge = edges[i].$3;
      final route = routes[i];
      final reversed = back.contains(i);
      final low = route.first;
      final high = route.last;
      // an edge drawn against the flow sits a little to the side, so it
      // doesn't hide the edge going the other way
      double shift(int node) => reversed
          ? math.min(10.0, math.max(0, across(sizes[node]) / 2 - 8))
          : 0;
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
      drawPath(
        path,
        edge.line == EdgeLine.thick ? stroke(line, 2.6) : edgePaint,
        dashed: edge.line == EdgeLine.dotted,
      );
      if (edge.arrow) {
        final forward = (point(1, 0) - point(0, 0)).direction;
        if (reversed) {
          drawHead(first, forward + math.pi, line);
        } else {
          drawHead(point(stops.last.$1, stops.last.$2), forward, line);
        }
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
              .merge(look.edgeLabelStyle),
          maxWidth: 140,
        );
        // on the middle of the edge's middle stretch, as Mermaid does
        final k = stops.length ~/ 2;
        final center =
            (point(stops[k - 1].$1, stops[k - 1].$2) +
                point(stops[k].$1, stops[k].$2)) /
            2;
        extra = math.max(extra, center.dx + painter.width / 2);
        edgeLabels.add((painter, center));
      }
    }
    // after every edge, so no later edge is drawn across a label: the line
    // under each label is erased, then the label is written in the gap
    final erase = Paint()..blendMode = BlendMode.clear;
    for (final (painter, center) in edgeLabels) {
      final gap = Rect.fromCenter(
        center: center,
        width: painter.width + 8,
        height: painter.height + 2,
      );
      ops.add((canvas) => canvas.drawRect(gap, erase));
      drawText(painter, center);
    }

    for (var i = 0; i < nodes.length; i++) {
      final center = point(middleOf(i), acrossOf[i]);
      final rect = Rect.fromCenter(
        center: center,
        width: sizes[i].width,
        height: sizes[i].height,
      );
      final path = _nodePath(nodes[i].shape, rect);
      final inside = Paint()..color = fill;
      final outline = stroke(border);
      ops.add(
        (canvas) => canvas
          ..drawPath(path, inside)
          ..drawPath(path, outline),
      );
      drawText(labels[i], center);
    }

    final width = horizontal ? totalAlong : totalAcross;
    final height = horizontal ? totalAcross : totalAlong;
    return (
      Size(math.max(width + _pad * 2, extra + _pad), height + _pad * 2),
      'Flowchart: ${nodes.map((n) => n.label.replaceAll('\n', ' ')).join(', ')}',
    );
  }

  // How far the outline is from the node's flat side, [offset] away from
  // the middle of that side: 0 for boxes, more for round and pointed ones.
  double _inset(NodeShape shape, Size size, double offset, bool horizontal) {
    if (offset == 0) return 0;
    final halfAcross = (horizontal ? size.height : size.width) / 2;
    final halfAlong = (horizontal ? size.width : size.height) / 2;
    return switch (shape) {
      NodeShape.diamond => offset / halfAcross * halfAlong,
      NodeShape.circle =>
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
    _ => Size(label.width + 28, label.height + 18),
  };

  Path _nodePath(NodeShape shape, Rect rect) {
    switch (shape) {
      case NodeShape.rect:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
      case NodeShape.rounded:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
      case NodeShape.stadium:
        return Path()..addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
        );
      case NodeShape.circle:
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
