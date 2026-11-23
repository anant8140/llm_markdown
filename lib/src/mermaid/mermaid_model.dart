// A small reader for the Mermaid diagrams that chat models write most:
// flowcharts (with subgraphs), state diagrams (with composite states and
// notes), class diagrams (with notes and cardinalities), ER diagrams,
// sequence diagrams, pie charts, gantt charts, mindmaps, timelines, git
// graphs, user journeys, quadrant charts, sankey diagrams and xy charts.
// Anything else, or anything these readers can't follow, returns null and
// is shown as code.

import 'dart:math' as math;

sealed class MermaidData {
  const MermaidData();
}

enum FlowDirection { down, up, right, left }

enum NodeShape {
  rect,
  rounded,
  stadium,
  circle,
  diamond,
  hexagon,
  // the black dot a state diagram starts at, and the ringed one it ends at
  start,
  end,
  // a class: its name, then its fields and methods
  classBox,
  // an ER entity: its name, then its attributes
  entity,
}

enum EdgeLine { solid, dotted, thick }

// what an edge ends in: an arrow, the hollow triangle of "inherits", or the
// diamonds of "is part of" (filled) and "has" (hollow)
// The ER ends: crow's feet for exactly one (||), zero or one (|o), one or
// many (}|) and zero or many (}o).
enum EdgeHead {
  none,
  arrow,
  triangle,
  filledDiamond,
  diamond,
  one,
  zeroOrOne,
  oneOrMany,
  zeroOrMany,
}

// The look a diagram gives a node (classDef, class, ":::", style) or an
// edge (linkStyle). Colors are 0xAARRGGBB; what the text doesn't set is
// null and drawn in the theme's colors.
class FlowStyle {
  const FlowStyle({
    this.fill,
    this.stroke,
    this.color,
    this.strokeWidth,
    this.dashed,
  });

  final int? fill;
  final int? stroke;

  // the text's color
  final int? color;
  final double? strokeWidth;

  // set by stroke-dasharray
  final bool? dashed;

  bool get isEmpty =>
      fill == null &&
      stroke == null &&
      color == null &&
      strokeWidth == null &&
      dashed == null;

  // this style with what [over] sets on top of it
  FlowStyle merge(FlowStyle over) => FlowStyle(
    fill: over.fill ?? fill,
    stroke: over.stroke ?? stroke,
    color: over.color ?? color,
    strokeWidth: over.strokeWidth ?? strokeWidth,
    dashed: over.dashed ?? dashed,
  );
}

class FlowNode {
  FlowNode(this.id) : label = id;

  final String id;
  String label;
  NodeShape shape = NodeShape.rect;

  // for a class: fields and methods, one per line
  final List<String> members = [];

  // for a class: "interface", "abstract", ...
  String? annotation;

  // from classDef, class, ":::" and style lines
  FlowStyle? style;
}

class FlowEdge {
  const FlowEdge(
    this.from,
    this.to, {
    this.label,
    this.line = EdgeLine.solid,
    this.head = EdgeHead.arrow,
    this.tail = EdgeHead.none,
    this.fromLabel,
    this.toLabel,
    this.style,
  });

  final String from;
  final String to;
  final String? label;

  // a class diagram's cardinalities ("1", "many"), drawn at each end
  final String? fromLabel;
  final String? toLabel;
  final EdgeLine line;

  // at [to]
  final EdgeHead head;

  // at [from]
  final EdgeHead tail;

  // from a linkStyle line
  final FlowStyle? style;

  FlowEdge styled(FlowStyle style) => FlowEdge(
    from,
    to,
    label: label,
    line: line,
    head: head,
    tail: tail,
    fromLabel: fromLabel,
    toLabel: toLabel,
    style: style,
  );
}

enum FlowKind { flowchart, state, classes, entities }

// A flowchart subgraph or a composite state: a titled box drawn around
// [members] (the nodes first mentioned inside it) and the groups whose
// [parent] it is.
class FlowGroup {
  FlowGroup(this.id, this.title, {this.parent});

  final String id;
  String title;
  final String? parent;
  final List<String> members = [];
}

// A note beside a state or class.
class FlowNote {
  const FlowNote(this.target, this.text, {this.side = NoteSide.right});

  final String target;
  final String text;

  // left or right
  final NoteSide side;
}

// Flowcharts, state, class and ER diagrams are all boxes joined by lines,
// so they are laid out the same way.
class FlowChart extends MermaidData {
  const FlowChart(
    this.direction,
    this.nodes,
    this.edges, {
    this.kind = FlowKind.flowchart,
    this.groups = const [],
    this.notes = const [],
  });

  final FlowDirection direction;
  final List<FlowNode> nodes;
  final List<FlowEdge> edges;
  final FlowKind kind;
  final List<FlowGroup> groups;
  final List<FlowNote> notes;
}

enum MessageHead { arrow, none, cross }

class SequenceMessage {
  const SequenceMessage(
    this.from,
    this.to,
    this.text, {
    required this.dashed,
    required this.head,
  });

  final String from;
  final String to;
  final String text;
  final bool dashed;
  final MessageHead head;
}

enum NoteSide { left, right, over }

class SequenceNote {
  const SequenceNote(this.side, this.participants, this.text);

  final NoteSide side;
  final List<String> participants;
  final String text;
}

// "loop Every minute", "alt Success", "else Failure" ...
class SequenceDivider {
  const SequenceDivider(this.text);

  final String text;
}

class SequenceDiagram extends MermaidData {
  const SequenceDiagram(this.participants, this.labels, this.items);

  final List<String> participants;
  final Map<String, String> labels;

  // SequenceMessage, SequenceNote or SequenceDivider, in order
  final List<Object> items;
}

class PieChart extends MermaidData {
  const PieChart(this.title, this.slices);

  final String? title;
  final List<(String, double)> slices;
}

class GanttTask {
  const GanttTask(
    this.name,
    this.start,
    this.end, {
    this.id,
    this.section,
    this.done = false,
    this.active = false,
    this.critical = false,
    this.milestone = false,
  });

  final String name;
  final String? id;
  final String? section;

  // UTC; [end] is where the bar stops
  final DateTime start;
  final DateTime end;
  final bool done;
  final bool active;
  final bool critical;
  final bool milestone;
}

class GanttChart extends MermaidData {
  const GanttChart(
    this.title,
    this.sections,
    this.tasks, {
    this.axisFormat,
    this.excluded = const [],
  });

  // the days left out by "excludes", each a UTC midnight
  final List<DateTime> excluded;

  final String? title;

  // how axis dates are written, as in "%b %e"
  final String? axisFormat;
  final List<String> sections;
  final List<GanttTask> tasks;
}

enum MindShape { plain, square, rounded, circle, bang, cloud, hexagon }

class MindNode {
  MindNode(this.text, [this.shape = MindShape.plain]);

  final String text;
  final MindShape shape;
  final List<MindNode> children = [];
}

class MindMap extends MermaidData {
  const MindMap(this.root);

  final MindNode root;
}

class TimelinePeriod {
  TimelinePeriod(this.text, {this.section});

  final String text;
  final String? section;
  final List<String> events = [];
}

class Timeline extends MermaidData {
  const Timeline(this.title, this.periods);

  final String? title;
  final List<TimelinePeriod> periods;
}

enum GitCommitType { normal, reverse, highlight }

class GitCommit {
  const GitCommit(
    this.branch, {
    this.parents = const [],
    this.label,
    this.tag,
    this.type = GitCommitType.normal,
    this.merge = false,
  });

  // an index into [GitGraph.branches]
  final int branch;

  // indexes into [GitGraph.commits]: the commit before it on its branch
  // (or the one it branched from), then for a merge the one merged in
  final List<int> parents;

  // its "id:" as written; null when the text gives none
  final String? label;
  final String? tag;
  final GitCommitType type;
  final bool merge;
}

class GitGraph extends MermaidData {
  const GitGraph(this.branches, this.commits);

  // "main" first, then the others in the order they were made
  final List<String> branches;
  final List<GitCommit> commits;
}

class JourneyTask {
  const JourneyTask(
    this.name,
    this.score, {
    this.actors = const [],
    this.section,
  });

  final String name;

  // 1 (bad) to 5 (good)
  final int score;
  final List<String> actors;
  final String? section;
}

class Journey extends MermaidData {
  const Journey(this.title, this.tasks);

  final String? title;
  final List<JourneyTask> tasks;
}

class QuadrantPoint {
  const QuadrantPoint(this.name, this.x, this.y);

  final String name;

  // 0 to 1, from the left and from the bottom
  final double x;
  final double y;
}

class QuadrantChart extends MermaidData {
  const QuadrantChart(
    this.title,
    this.quadrants,
    this.points, {
    this.xLow,
    this.xHigh,
    this.yLow,
    this.yHigh,
  });

  final String? title;

  // quadrant-1 to quadrant-4: top right, top left, bottom left, bottom
  // right
  final List<String?> quadrants;
  final List<QuadrantPoint> points;
  final String? xLow;
  final String? xHigh;
  final String? yLow;
  final String? yHigh;
}

class SankeyLink {
  const SankeyLink(this.source, this.target, this.value);

  // indexes into [Sankey.nodes]
  final int source;
  final int target;
  final double value;
}

class Sankey extends MermaidData {
  const Sankey(this.nodes, this.links);

  final List<String> nodes;
  final List<SankeyLink> links;
}

class XySeries {
  const XySeries(this.values, {required this.bar});

  final List<double> values;

  // bars, or a line
  final bool bar;
}

class XyChart extends MermaidData {
  const XyChart(
    this.series, {
    this.title,
    this.xTitle,
    this.yTitle,
    this.categories,
    this.xRange,
    this.yRange,
  });

  final List<XySeries> series;
  final String? title;
  final String? xTitle;
  final String? yTitle;

  // the names along the x axis, or null for numbers ([xRange], or 1, 2 ...)
  final List<String>? categories;
  final (double, double)? xRange;
  final (double, double)? yRange;
}

final RegExp _comment = RegExp(r'%%.*$', multiLine: true);
final RegExp _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);

/// Reads [source], or returns null when it isn't a diagram this package
/// draws.
MermaidData? parseMermaid(String source) {
  // a mindmap is read from the indentation, so the lines are kept untrimmed
  // here too
  final raw = source
      .replaceAll(_comment, '')
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
  final lines = raw.map((line) => line.trim()).toList();
  // an optional "---\ntitle: x\n---" block comes first
  if (lines.isNotEmpty && lines.first == '---') {
    final end = lines.indexOf('---', 1);
    if (end == -1) return null;
    lines.removeRange(0, end + 1);
    raw.removeRange(0, end + 1);
  }
  if (lines.isEmpty) return null;
  final head = lines.first;
  final flow = RegExp(
    r'^(?:graph|flowchart)(?:\s+(TB|TD|BT|LR|RL))?\s*;?\s*(.*)$',
    caseSensitive: false,
  ).firstMatch(head);
  if (flow != null) {
    return _flowChart(flow[1], [
      if (flow[2]!.isNotEmpty) flow[2]!,
      ...lines.skip(1),
    ]);
  }
  if (RegExp(r'^stateDiagram(?:-v2)?\s*$').hasMatch(head)) {
    return _state(lines.skip(1));
  }
  if (RegExp(r'^classDiagram(?:-v2)?\s*$').hasMatch(head)) {
    return _classes(lines.skip(1));
  }
  if (RegExp(r'^sequenceDiagram\b').hasMatch(head)) {
    return _sequence(lines.skip(1));
  }
  if (RegExp(r'^pie\b').hasMatch(head)) return _pie(lines);
  if (RegExp(r'^erDiagram\s*$').hasMatch(head)) return _er(lines.skip(1));
  if (RegExp(r'^gantt\s*$').hasMatch(head)) return _gantt(lines.skip(1));
  if (RegExp(r'^mindmap\s*$').hasMatch(head)) return _mindmap(raw.skip(1));
  if (RegExp(r'^timeline\s*$').hasMatch(head)) {
    return _timeline(lines.skip(1));
  }
  if (RegExp(r'^gitGraph\s*(?:LR|TB|BT)?\s*:?$').hasMatch(head)) {
    return _gitGraph(lines.skip(1));
  }
  if (RegExp(r'^journey\s*$').hasMatch(head)) return _journey(lines.skip(1));
  if (RegExp(r'^quadrantChart\s*$').hasMatch(head)) {
    return _quadrant(lines.skip(1));
  }
  if (RegExp(r'^sankey(?:-beta)?\s*$').hasMatch(head)) {
    return _sankey(lines.skip(1));
  }
  if (RegExp(
    r'^xychart(?:-beta)?(?:\s+(?:horizontal|vertical))?\s*$',
  ).hasMatch(head)) {
    return _xyChart(lines.skip(1));
  }
  return null;
}

String _label(String raw) {
  var text = raw.trim();
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    text = text.substring(1, text.length - 1);
  }
  return text
      .replaceAll(_lineBreak, '\n')
      .replaceAll('#quot;', '"')
      .replaceAll('&amp;', '&')
      .trim();
}

const _ignoredFlow = [
  'subgraph',
  'end',
  'direction',
  'classDef',
  'class ',
  'style ',
  'linkStyle',
  'click ',
  'accTitle',
  'accDescr',
];

final RegExp _nodeId = RegExp(r'[\w\u0080-￿]+');

// (opener, closer, shape); longer openers first
const _shapes = [
  ('([', '])', NodeShape.stadium),
  ('((', '))', NodeShape.circle),
  ('[[', ']]', NodeShape.rect),
  ('[(', ')]', NodeShape.rounded),
  ('{{', '}}', NodeShape.hexagon),
  ('[', ']', NodeShape.rect),
  ('(', ')', NodeShape.rounded),
  ('{', '}', NodeShape.diamond),
  ('>', ']', NodeShape.rect),
];

// A -- text --> B, A -. text .-> B, A == text ==> B
final RegExp _textEdge = RegExp(
  r'\s*(--|-\.|==)\s+(.+?)\s+(-{2,}|\.-+|={2,})(>)?\s*',
);

// A --> B, A --- B, A -.-> B, A ==> B, A --x B, each with an optional |text|
final RegExp _plainEdge = RegExp(
  r'\s*<?(-{2,}|-\.+-|={2,})(>|x\b|o\b)?\s*(?:\|([^|]*)\|)?\s*',
);

final RegExp _subgraph = RegExp(r'^subgraph\b\s*(.*)$');
final RegExp _namedSubgraph = RegExp(r'^([\w\u0080-\uffff-]+)\s*\[(.*)\]$');

FlowChart? _flowChart(String? direction, List<String> lines) {
  final nodes = <String, FlowNode>{};
  final edges = <FlowEdge>[];
  final groups = <String, FlowGroup>{};
  // the subgraphs the line is inside, innermost last
  final open = <FlowGroup>[];
  final styling = _Styling();

  FlowNode newNode(String id) {
    // a node belongs to the innermost subgraph it is first mentioned in
    final group = open.lastOrNull;
    if (group != null && group.id != id) group.members.add(id);
    return FlowNode(id);
  }

  for (final line in lines) {
    for (final statement in line.split(';')) {
      final text = statement.trim();
      if (text.isEmpty) continue;
      final sub = _subgraph.firstMatch(text);
      if (sub != null) {
        // "subgraph id [title]", "subgraph "title"" or "subgraph title"
        final rest = sub[1]!.trim();
        final named = _namedSubgraph.firstMatch(rest);
        final id =
            named?[1] ?? (rest.isEmpty ? ' ${groups.length}' : _label(rest));
        final title = named != null ? _label(named[2]!) : _label(rest);
        open.add(
          groups.putIfAbsent(
            id,
            () => FlowGroup(id, title, parent: open.lastOrNull?.id),
          ),
        );
        continue;
      }
      if (text == 'end') {
        if (open.isNotEmpty) open.removeLast();
        continue;
      }
      if (styling.read(text)) continue;
      if (_ignoredFlow.any(
        (word) => text == word.trim() || text.startsWith(word),
      )) {
        continue;
      }
      var at = 0;

      List<String>? group() {
        final ids = <String>[];
        while (true) {
          final id = _nodeId.matchAsPrefix(text, at);
          if (id == null) return ids.isEmpty ? null : ids;
          at = id.end;
          final node = nodes.putIfAbsent(id[0]!, () => newNode(id[0]!));
          for (final (open, close, shape) in _shapes) {
            if (!text.startsWith(open, at)) continue;
            final start = at + open.length;
            // a quoted label may hold the closing bracket itself
            final quoted = text.startsWith('"', start)
                ? text.indexOf('"', start + 1)
                : -1;
            final end = text.indexOf(close, quoted == -1 ? start : quoted);
            if (end == -1) break;
            node
              ..label = _label(text.substring(start, end))
              ..shape = shape;
            at = end + close.length;
            break;
          }
          // A:::someClass
          final styled = RegExp(r':::([\w-]+)').matchAsPrefix(text, at);
          if (styled != null) {
            styling.tag(node.id, styled[1]!);
            at = styled.end;
          }
          final and = RegExp(r'\s*&\s*').matchAsPrefix(text, at);
          ids.add(node.id);
          if (and == null) return ids;
          at = and.end;
        }
      }

      var from = group();
      while (from != null && at < text.length) {
        String? label;
        EdgeLine line;
        bool arrow;
        final withText = _textEdge.matchAsPrefix(text, at);
        if (withText != null) {
          label = _label(withText[2]!);
          line = _lineOf(withText[1]!);
          arrow = withText[4] != null;
          at = withText.end;
        } else {
          final plain = _plainEdge.matchAsPrefix(text, at);
          if (plain == null) break;
          final inline = plain[3];
          label = inline == null ? null : _label(inline);
          line = _lineOf(plain[1]!);
          arrow = plain[2] != null;
          at = plain.end;
        }
        final to = group();
        if (to == null) break;
        for (final a in from) {
          for (final b in to) {
            edges.add(
              FlowEdge(
                a,
                b,
                label: label == null || label.isEmpty ? null : label,
                line: line,
                head: arrow ? EdgeHead.arrow : EdgeHead.none,
              ),
            );
          }
        }
        from = to;
      }
    }
  }
  if (nodes.isEmpty) return null;
  styling
    ..apply(nodes.values)
    ..applyLinks(edges);
  // An edge to a subgraph's id (A --> sub1) is drawn to the subgraph's box,
  // as Mermaid does: such an id is kept as a node here, and the view draws
  // the box in its place.
  return FlowChart(
    _direction(direction),
    nodes.values.toList(),
    edges,
    groups: groups.values.toList(),
  );
}

FlowDirection _direction(String? word) => switch (word?.toUpperCase()) {
  'BT' => FlowDirection.up,
  'LR' => FlowDirection.right,
  'RL' => FlowDirection.left,
  _ => FlowDirection.down,
};

final RegExp _directionLine = RegExp(
  r'^direction\s+(TB|TD|BT|LR|RL)$',
  caseSensitive: false,
);

// ---- state diagrams ---------------------------------------------------

final RegExp _stateId = RegExp(r'^(\[\*\]|[\w\u0080-\uffff.-]+)$');
final RegExp _transition = RegExp(
  r'^(\[\*\]|[\w\u0080-\uffff.-]+)\s*-->\s*(\[\*\]|[\w\u0080-\uffff.-]+)\s*(?::\s*(.*))?$',
);
final RegExp _stateAlias = RegExp(
  r'^state\s+"([^"]*)"\s+as\s+([\w\u0080-\uffff.-]+)',
);
final RegExp _stateKind = RegExp(
  r'^state\s+([\w\u0080-\uffff.-]+)\s*<<(\w+)>>\s*$',
);
final RegExp _stateOpen = RegExp(
  r'^state\s+(?:"[^"]*"\s+as\s+)?([\w\u0080-\uffff.-]+)\s*\{\s*$',
);
final RegExp _stateText = RegExp(r'^([\w\u0080-\uffff.-]+)\s*:\s*(.+)$');
final RegExp _stateNote = RegExp(
  r'^note\s+(right|left)\s+of\s+([\w\u0080-\uffff.-]+)\s*(?::\s*(.*))?$',
  caseSensitive: false,
);

FlowChart? _state(Iterable<String> lines) {
  final nodes = <String, FlowNode>{};
  final edges = <FlowEdge>[];
  String? direction;
  // the composite states the line is inside; each has its own start and end
  final scope = <String>[];
  final groups = <String, FlowGroup>{};
  final notes = <FlowNote>[];
  var inNote = false;
  // a note on several lines: its target, side and lines so far
  RegExpMatch? noteHead;
  final noteLines = <String>[];
  final styling = _Styling();

  FlowNode made(String id) {
    // a state belongs to the innermost composite it is first mentioned in
    if (scope.isNotEmpty) groups[scope.last]!.members.add(id);
    return FlowNode(id);
  }

  FlowNode node(String id, {required bool from}) {
    if (id != '[*]') return nodes.putIfAbsent(id, () => made(id));
    final key = '[*]${from ? 'start' : 'end'}@${scope.join('/')}';
    return nodes.putIfAbsent(
      key,
      () => made(key)
        ..label = ''
        ..shape = from ? NodeShape.start : NodeShape.end,
    );
  }

  NoteSide side(String word) =>
      word.toLowerCase() == 'left' ? NoteSide.left : NoteSide.right;

  for (final written in lines) {
    var line = written;
    if (inNote) {
      if (RegExp(r'^end\s+note$', caseSensitive: false).hasMatch(line)) {
        inNote = false;
        final head = noteHead;
        if (head != null && noteLines.isNotEmpty) {
          notes.add(
            FlowNote(head[2]!, noteLines.join('\n'), side: side(head[1]!)),
          );
        }
      } else {
        noteLines.add(_label(line));
      }
      continue;
    }
    if (line.toLowerCase().startsWith('note ')) {
      final note = _stateNote.firstMatch(line);
      if (note != null && note[3] != null) {
        notes.add(FlowNote(note[2]!, _label(note[3]!), side: side(note[1]!)));
      } else if (!line.contains(':')) {
        // a note on several lines runs to "end note"
        inNote = true;
        noteHead = note;
        noteLines.clear();
      }
      continue;
    }
    if (styling.read(line)) continue;
    line = styling.untag(line);
    final turned = _directionLine.firstMatch(line);
    if (turned != null) {
      if (scope.isEmpty) direction = turned[1];
      continue;
    }
    final open = _stateOpen.firstMatch(line);
    if (open != null) {
      node(open[1]!, from: true);
      final alias = _stateAlias.firstMatch(line);
      if (alias != null) nodes[open[1]!]!.label = _label(alias[1]!);
      groups.putIfAbsent(
        open[1]!,
        () => FlowGroup(open[1]!, '', parent: scope.lastOrNull),
      );
      scope.add(open[1]!);
      continue;
    }
    if (line == '}') {
      if (scope.isNotEmpty) scope.removeLast();
      continue;
    }
    final alias = _stateAlias.firstMatch(line);
    if (alias != null) {
      node(alias[2]!, from: true).label = _label(alias[1]!);
      continue;
    }
    final kind = _stateKind.firstMatch(line);
    if (kind != null) {
      final state = node(kind[1]!, from: true);
      switch (kind[2]!.toLowerCase()) {
        case 'choice':
          state
            ..shape = NodeShape.diamond
            ..label = '';
        case 'fork' || 'join':
          state
            ..shape = NodeShape.rect
            ..label = '';
      }
      continue;
    }
    final step = _transition.firstMatch(line);
    if (step != null) {
      final from = node(step[1]!, from: true);
      final to = node(step[2]!, from: false);
      final text = step[3] == null ? '' : _label(step[3]!);
      edges.add(FlowEdge(from.id, to.id, label: text.isEmpty ? null : text));
      continue;
    }
    final described = _stateText.firstMatch(line);
    if (described != null) {
      final state = node(described[1]!, from: true);
      // "A : text" twice puts the texts under each other
      final text = _label(described[2]!);
      state.label = state.label == state.id ? text : '${state.label}\n$text';
      continue;
    }
    if (_stateId.hasMatch(line) && line != '[*]') node(line, from: true);
    // "--" between concurrent regions and the like change nothing drawn
    // here
  }
  if (nodes.isEmpty) return null;
  styling.apply(nodes.values);
  for (final state in nodes.values) {
    if (state.shape == NodeShape.rect && state.label.isNotEmpty) {
      state.shape = NodeShape.rounded;
    }
  }
  // a composite state's box is titled with its name
  for (final group in groups.values) {
    group.title = nodes[group.id]!.label;
  }
  return FlowChart(
    _direction(direction),
    nodes.values.toList(),
    edges,
    kind: FlowKind.state,
    groups: groups.values.toList(),
    notes: notes,
  );
}

// ---- class diagrams ---------------------------------------------------

const _className = r'[\w\u0080-\uffff]+(?:~[^~]*~)?';
final RegExp _classOpen = RegExp(
  '^class\\s+($_className)(?:\\s*\\["([^"]*)"\\])?\\s*(\\{)?\\s*(\\})?\$',
);
final RegExp _relation = RegExp(
  '^($_className)\\s*(?:"([^"]*)")?\\s*'
  r'(<\|--|<\|\.\.|\*--|o--|<--|<\.\.|--\|>|\.\.\|>|--\*|--o|-->|\.\.>|--|\.\.)'
  '\\s*(?:"([^"]*)")?\\s*($_className)\\s*(?::\\s*(.*))?\$',
);
final RegExp _memberLine = RegExp('^($_className)\\s*:\\s*(.+)\$');
final RegExp _classNote = RegExp(
  '^note\\s+for\\s+($_className)\\s+"(.*)"\$',
  caseSensitive: false,
);
final RegExp _annotationLine = RegExp(
  '^<<\\s*([^>]+?)\\s*>>\\s*($_className)?\$',
);

EdgeHead _mark(String mark) => switch (mark) {
  '<|' || '|>' => EdgeHead.triangle,
  '*' => EdgeHead.filledDiamond,
  'o' => EdgeHead.diamond,
  '<' || '>' => EdgeHead.arrow,
  _ => EdgeHead.none,
};

// Person~T~ is written Person<T>
String _classLabel(String id) =>
    id.replaceAllMapped(RegExp(r'~([^~]*)~'), (m) => '<${m[1]}>');

FlowChart? _classes(Iterable<String> lines) {
  final nodes = <String, FlowNode>{};
  final edges = <FlowEdge>[];
  String? direction;
  FlowNode? open;
  final notes = <FlowNote>[];
  final styling = _Styling();

  FlowNode classNode(String raw) {
    final id = raw.replaceAll(RegExp(r'~[^~]*~'), '');
    final node = nodes.putIfAbsent(
      id,
      () => FlowNode(id)..shape = NodeShape.classBox,
    );
    if (raw != id) node.label = _classLabel(raw);
    return node;
  }

  for (final written in lines) {
    var line = written;
    if (open != null) {
      if (line == '}') {
        open = null;
        continue;
      }
      final annotation = _annotationLine.firstMatch(line);
      if (annotation != null) {
        open.annotation = annotation[1];
      } else {
        open.members.add(_label(line));
      }
      continue;
    }
    if (styling.read(line, classLines: false)) continue;
    line = styling.untag(line);
    final turned = _directionLine.firstMatch(line);
    if (turned != null) {
      direction = turned[1];
      continue;
    }
    final declared = _classOpen.firstMatch(line);
    if (declared != null) {
      final node = classNode(declared[1]!);
      if (declared[2] != null) node.label = _label(declared[2]!);
      if (declared[3] != null && declared[4] == null) open = node;
      continue;
    }
    final note = _classNote.firstMatch(line);
    if (note != null) {
      notes.add(
        FlowNote(
          note[1]!.replaceAll(RegExp(r'~[^~]*~'), ''),
          _label(note[2]!.replaceAll(r'\n', '\n')),
        ),
      );
      continue;
    }
    final annotation = _annotationLine.firstMatch(line);
    if (annotation != null) {
      if (annotation[2] != null) {
        classNode(annotation[2]!).annotation = annotation[1];
      }
      continue;
    }
    final relation = _relation.firstMatch(line);
    if (relation != null) {
      final from = classNode(relation[1]!);
      final to = classNode(relation[5]!);
      final arrow = relation[3]!;
      final body = arrow.contains('..') ? '..' : '--';
      final at = arrow.indexOf(body);
      String? text(String? raw) {
        final label = raw == null ? '' : _label(raw);
        return label.isEmpty ? null : label;
      }

      edges.add(
        FlowEdge(
          from.id,
          to.id,
          label: text(relation[6]),
          fromLabel: text(relation[2]),
          toLabel: text(relation[4]),
          line: body == '..' ? EdgeLine.dotted : EdgeLine.solid,
          tail: _mark(arrow.substring(0, at)),
          head: _mark(arrow.substring(at + 2)),
        ),
      );
      continue;
    }
    final member = _memberLine.firstMatch(line);
    if (member != null) {
      classNode(member[1]!).members.add(_label(member[2]!));
      continue;
    }
    // link, click, callback ... change nothing drawn here
  }
  if (nodes.isEmpty) return null;
  styling.apply(nodes.values);
  return FlowChart(
    _direction(direction),
    nodes.values.toList(),
    edges,
    kind: FlowKind.classes,
    notes: notes,
  );
}

EdgeLine _lineOf(String body) => body.contains('.')
    ? EdgeLine.dotted
    : body.contains('=')
    ? EdgeLine.thick
    : EdgeLine.solid;

final RegExp _participant = RegExp(
  r'^(?:participant|actor)\s+(.+?)(?:\s+as\s+(.+))?$',
  caseSensitive: false,
);
final RegExp _message = RegExp(
  r'^(.+?)\s*(-->>|->>|-->|->|--x|-x|--\)|-\))\s*[+-]?\s*(.+?)\s*:\s*(.*)$',
);
final RegExp _note = RegExp(
  r'^note\s+(right of|left of|over)\s+([^:]+):\s*(.*)$',
  caseSensitive: false,
);
final RegExp _block = RegExp(
  r'^(loop|alt|else|opt|par|and|critical|option|break)\b\s*(.*)$',
  caseSensitive: false,
);

SequenceDiagram? _sequence(Iterable<String> lines) {
  final participants = <String>[];
  final labels = <String, String>{};
  final items = <Object>[];
  void know(String id) {
    if (!participants.contains(id)) participants.add(id);
  }

  for (final line in lines) {
    final participant = _participant.firstMatch(line);
    if (participant != null) {
      final id = participant[1]!.trim();
      know(id);
      final label = participant[2];
      if (label != null) labels[id] = _label(label);
      continue;
    }
    final note = _note.firstMatch(line);
    if (note != null) {
      final over = note[2]!.split(',').map((id) => id.trim()).toList();
      over.forEach(know);
      items.add(
        SequenceNote(
          switch (note[1]!.toLowerCase()) {
            'right of' => NoteSide.right,
            'left of' => NoteSide.left,
            _ => NoteSide.over,
          },
          over,
          _label(note[3]!),
        ),
      );
      continue;
    }
    final block = _block.firstMatch(line);
    if (block != null) {
      final text = block[2]!.trim();
      final word = block[1]!.toLowerCase();
      items.add(SequenceDivider(text.isEmpty ? word : '$word: $text'));
      continue;
    }
    final message = _message.firstMatch(line);
    if (message != null) {
      final from = message[1]!.trim();
      final to = message[3]!.trim();
      know(from);
      know(to);
      final arrow = message[2]!;
      items.add(
        SequenceMessage(
          from,
          to,
          _label(message[4]!),
          dashed: arrow.startsWith('--'),
          head: arrow.endsWith('x')
              ? MessageHead.cross
              : arrow.endsWith('>>') || arrow.endsWith(')')
              ? MessageHead.arrow
              : MessageHead.none,
        ),
      );
    }
    // activate, deactivate, autonumber, end ... change nothing drawn here
  }
  if (participants.isEmpty) return null;
  return SequenceDiagram(participants, labels, items);
}

final RegExp _slice = RegExp(r'^"([^"]*)"\s*:\s*(-?\d+(?:\.\d+)?)$');

PieChart? _pie(List<String> lines) {
  String? title;
  final slices = <(String, double)>[];
  for (final line in lines) {
    final named = RegExp(r'\btitle\s+(.+)$').firstMatch(line);
    final slice = _slice.firstMatch(line);
    if (slice != null) {
      final value = double.parse(slice[2]!);
      if (value > 0) slices.add((slice[1]!, value));
    } else if (named != null) {
      title = named[1]!.trim();
    }
  }
  if (slices.isEmpty) return null;
  return PieChart(title, slices);
}

// ---- ER diagrams ------------------------------------------------------

// a bare or "quoted name"
const _entityName = r'(?:"([^"\n]+)"|(\d+\.\d+(?![\w.])|[\w\u0080-\uffff-]+))';

// Cardinalities as Mermaid's lexer reads them, words and symbols; longer
// words first.
const _cardinality =
    r'(?:only one|zero or one|one or zero|one or more|one or many|'
    r'zero or more|zero or many|many\(0\)|many\(1\)|many|one|1\+|0\+|1|'
    r'u(?=[.\-|])|'
    r'\|o|o\||\|\||\}o|o\}|\}\||\|\}|o\{|\{o|\|\{|\{\|)';
final RegExp _entityOpen = RegExp(
  '^$_entityName(?:\\s*\\[([^\\]]*)\\])?\\s*(\\{\\s*(\\})?)?\$',
);
final RegExp _relationship = RegExp(
  '^$_entityName\\s*($_cardinality)\\s*'
  r'(--|\.\.|\.-|-\.|optionally to\b|to\b)'
  '\\s*($_cardinality)\\s*$_entityName\\s*(?::\\s*(.*))?\$',
);
final RegExp _attribute = RegExp(
  r'^([\w\u0080-￿()\[\]*-]+)\s+([\w\u0080-￿()\[\]*-]+)'
  r'(?:\s+((?:PK|FK|UK)(?:\s*,\s*(?:PK|FK|UK))*))?(?:\s+"([^"]*)")?$',
);

// "u" is Mermaid's MD_PARENT, which its renderer draws no marker for
EdgeHead _cardinalityOf(String mark) => switch (mark) {
  'u' => EdgeHead.none,
  'only one' || 'one' || '1' || '||' => EdgeHead.one,
  'zero or one' || 'one or zero' || '|o' || 'o|' => EdgeHead.zeroOrOne,
  'one or more' ||
  'one or many' ||
  'many(1)' ||
  '1+' ||
  '}|' ||
  '|}' ||
  '|{' ||
  '{|' => EdgeHead.oneOrMany,
  _ => EdgeHead.zeroOrMany,
};

// Lines it can't read (styling, excludes, ...) are left out; it is null
// only when no entity is found.
FlowChart? _er(Iterable<String> lines) {
  final nodes = <String, FlowNode>{};
  final edges = <FlowEdge>[];
  String? direction;
  FlowNode? open;

  FlowNode entity(String? quoted, String? bare) {
    final id = quoted ?? bare!;
    return nodes.putIfAbsent(id, () => FlowNode(id)..shape = NodeShape.entity);
  }

  for (final line in lines) {
    if (open != null) {
      if (line == '}') {
        open = null;
        continue;
      }
      final attribute = _attribute.firstMatch(line);
      if (attribute == null) continue;
      final keys = attribute[3]?.split(',').map((k) => k.trim()).join(', ');
      open.members.add(
        [
          attribute[1],
          attribute[2],
          keys,
          if (attribute[4] != null) '"${attribute[4]}"',
        ].nonNulls.join(' '),
      );
      continue;
    }
    final turned = _directionLine.firstMatch(line);
    if (turned != null) {
      direction = turned[1];
      continue;
    }
    final relation = _relationship.firstMatch(line);
    if (relation != null) {
      final from = entity(relation[1], relation[2]);
      final to = entity(relation[6], relation[7]);
      final label = relation[8] == null ? '' : _label(relation[8]!);
      final body = relation[4]!;
      edges.add(
        FlowEdge(
          from.id,
          to.id,
          label: label.isEmpty ? null : label,
          line: body == '--' || body == 'to' ? EdgeLine.solid : EdgeLine.dotted,
          tail: _cardinalityOf(relation[3]!),
          head: _cardinalityOf(relation[5]!),
        ),
      );
      continue;
    }
    final declared = _entityOpen.firstMatch(line);
    if (declared != null) {
      final node = entity(declared[1], declared[2]);
      if (declared[3] != null) node.label = _label(declared[3]!);
      if (declared[4] != null && declared[5] == null) open = node;
      continue;
    }
    // title, styling and anything else unknown change nothing drawn here
  }
  if (nodes.isEmpty) return null;
  return FlowChart(
    _direction(direction),
    nodes.values.toList(),
    edges,
    kind: FlowKind.entities,
  );
}

// ---- gantt charts -----------------------------------------------------

final RegExp _span = RegExp(r'^(\d+(?:\.\d+)?)(ms|s|m|h|d|w|M|y)$');
final RegExp _ganttTask = RegExp(r'^([^:]+?)\s*:\s*(.+)$');
const _ganttTags = {'done', 'active', 'crit', 'milestone'};
const _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

const _monthLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

// Reads dates written in [format], with the dayjs tokens YYYY YY MMMM MMM
// MM M DD D HH H mm m ss s, X (unix seconds) and x (unix milliseconds),
// and any other non-letters between; null for a format with other
// tokens. A missing year, month or day is taken from 1970-01-01.
DateTime? Function(String)? _dateReader(String format) {
  const tokens = [
    'YYYY',
    'MMMM',
    'MMM',
    'YY',
    'MM',
    'DD',
    'HH',
    'mm',
    'ss',
    'M',
    'D',
    'H',
    'm',
    's',
    'X',
    'x',
  ];
  final fields = <String>[];
  final pattern = StringBuffer('^');
  for (var at = 0; at < format.length;) {
    final token = tokens
        .where((token) => format.startsWith(token, at))
        .firstOrNull;
    if (token != null) {
      fields.add(token);
      pattern.write(switch (token) {
        'YYYY' => r'(\d{4})',
        'MMMM' => '(${_monthLong.join('|')})',
        'MMM' => '(${_monthNames.join('|')})',
        'X' => r'(-?\d{1,11}(?:\.\d{1,3})?)',
        'x' => r'(-?\d{1,14})',
        'M' || 'D' || 'H' || 'm' || 's' => r'(\d{1,2})',
        _ => r'(\d{2})',
      });
      at += token.length;
    } else if (RegExp('[A-Za-z]').hasMatch(format[at])) {
      return null;
    } else {
      pattern.write(RegExp.escape(format[at]));
      at++;
    }
  }
  if (fields.isEmpty) return null;
  final regex = RegExp('$pattern\$', caseSensitive: false);
  return (text) {
    final match = regex.firstMatch(text);
    if (match == null) return null;
    final value = <String, int>{};
    for (var i = 0; i < fields.length; i++) {
      final raw = match[i + 1]!;
      switch (fields[i]) {
        case 'X':
          return DateTime.fromMillisecondsSinceEpoch(
            (double.parse(raw) * 1000).round(),
            isUtc: true,
          );
        case 'x':
          return DateTime.fromMillisecondsSinceEpoch(
            int.parse(raw),
            isUtc: true,
          );
        case 'MMMM' || 'MMM':
          final names = fields[i] == 'MMMM' ? _monthLong : _monthNames;
          value['M'] =
              names.indexWhere((n) => n.toLowerCase() == raw.toLowerCase()) + 1;
        case 'YY':
          // as dayjs: 69 and up are the 1900s
          final year = int.parse(raw);
          value['Y'] = year + (year > 68 ? 1900 : 2000);
        case final token:
          value[token[0]] = int.parse(raw);
      }
    }
    final (year, month, day, hour, minute, second) = (
      value['Y'] ?? 1970,
      value['M'] ?? 1,
      value['D'] ?? 1,
      value['H'] ?? 0,
      value['m'] ?? 0,
      value['s'] ?? 0,
    );
    final date = DateTime.utc(year, month, day, hour, minute, second);
    // 2024-02-30 is not a day, nor 25:00 a time
    final same =
        date.year == year &&
        date.month == month &&
        date.day == day &&
        date.hour == hour &&
        date.minute == minute &&
        date.second == second;
    return same ? date : null;
  };
}

// Dates in the chart's dateFormat (YYYY, MM, DD, HH, mm, ss) and spans in
// ms, s, m, h, d or w. "after" may name a task further down. Excludes
// (weekends, weekday names, dates) and includes push a span's end past the
// days left out, as Mermaid does; an end written as a date stays.
// Anything else returns null and the chart is shown as code.
GanttChart? _gantt(Iterable<String> lines) {
  String? title;
  String? section;
  String? axisFormat;
  var read = _dateReader('YYYY-MM-DD')!;
  var inclusive = false;
  final excludes = <String>{};
  final includes = <String>{};
  var weekendStart = 6;
  final sections = <String>[];
  // (name, section, tags, id, start, end) as written
  final specs = <(String, String?, Set<String>, String?, String?, String)>[];
  for (final line in lines) {
    final word = RegExp(r'^(\w+)\b\s*:?\s*(.*)$').firstMatch(line);
    final rest = word?[2]!.trim() ?? '';
    switch (word?[1]) {
      case 'title':
        title = rest;
        continue;
      case 'dateFormat':
        final reader = _dateReader(rest);
        if (reader == null) return null;
        read = reader;
        continue;
      case 'axisFormat':
        axisFormat = rest;
        continue;
      case 'section':
        section = rest;
        sections.add(rest);
        continue;
      case 'inclusiveEndDates':
        inclusive = true;
        continue;
      case 'excludes' || 'includes':
        (word![1] == 'excludes' ? excludes : includes).addAll(
          rest.toLowerCase().split(RegExp(r'[\s,]+')).where((w) => w != ''),
        );
        continue;
      case 'weekend':
        weekendStart = rest.toLowerCase() == 'friday' ? 5 : 6;
        continue;
      case 'tickInterval' ||
          'todayMarker' ||
          'weekday' ||
          'displayMode' ||
          'topAxis' ||
          'accTitle' ||
          'accDescr':
        continue;
    }
    final task = _ganttTask.firstMatch(line);
    if (task == null) return null;
    final parts = task[2]!.split(',').map((part) => part.trim()).toList();
    final tags = <String>{};
    while (parts.isNotEmpty && _ganttTags.contains(parts.first)) {
      tags.add(parts.removeAt(0));
    }
    final (String?, String?) idAndStart = switch (parts.length) {
      1 => (null, null),
      2 => (null, parts[0]),
      3 => (parts[0], parts[1]),
      _ => (null, '\u0000'),
    };
    if (idAndStart.$2 == '\u0000') return null;
    specs.add((
      _label(task[1]!),
      section,
      tags,
      idAndStart.$1,
      idAndStart.$2,
      parts.last,
    ));
  }
  if (specs.isEmpty) return null;

  String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  bool skipped(DateTime d) {
    if (includes.contains(day(d))) return false;
    final weekday = d.weekday; // 1 = Monday
    final weekend = weekday == weekendStart || weekday == weekendStart % 7 + 1;
    return (excludes.contains('weekends') && weekend) ||
        excludes.contains(_weekdays[weekday - 1]) ||
        excludes.contains(day(d));
  }

  final ids = {
    for (final spec in specs)
      if (spec.$4 != null) spec.$4!,
  };
  final tasks = List<GanttTask?>.filled(specs.length, null);
  final byId = <String, GanttTask>{};
  // a task can wait on one further down, so it is read in rounds
  for (var round = 0; round <= specs.length; round++) {
    var progress = false;
    for (var k = 0; k < specs.length; k++) {
      if (tasks[k] != null) continue;
      final (name, section, tags, id, startText, endText) = specs[k];
      DateTime? start;
      if (startText == null) {
        // right after the task before
        if (k == 0) return null;
        start = tasks[k - 1]?.end;
        if (start == null) continue;
      } else if (startText.startsWith('after ')) {
        final refs = startText.substring(6).trim().split(RegExp(r'\s+'));
        if (refs.any((ref) => !ids.contains(ref))) return null;
        if (refs.any((ref) => !byId.containsKey(ref))) continue;
        for (final ref in refs) {
          final end = byId[ref]!.end;
          if (start == null || end.isAfter(start)) start = end;
        }
      } else {
        start = read(startText);
        if (start == null) return null;
      }
      var end = read(endText);
      if (end != null) {
        if (inclusive) end = end.add(const Duration(days: 1));
      } else if (endText.startsWith('until ')) {
        // up to the earliest start of the tasks named
        final refs = endText.substring(6).trim().split(RegExp(r'\s+'));
        if (refs.any((ref) => !ids.contains(ref))) return null;
        if (refs.any((ref) => !byId.containsKey(ref))) continue;
        for (final ref in refs) {
          final begin = byId[ref]!.start;
          if (end == null || begin.isBefore(end)) end = begin;
        }
      } else {
        final span = _span.firstMatch(endText);
        if (span == null) return null;
        final amount = double.parse(span[1]!);
        if (span[2] == 'M' || span[2] == 'y') {
          // months and years by the calendar, whole ones only
          if (amount != amount.roundToDouble()) return null;
          final months = amount.round() * (span[2] == 'y' ? 12 : 1);
          // Jan 31 and a month is Feb 29 (or 28), as dayjs counts
          final month = DateTime.utc(start!.year, start.month + months);
          final last = DateTime.utc(month.year, month.month + 1, 0).day;
          end = DateTime.utc(
            month.year,
            month.month,
            math.min(start.day, last),
            start.hour,
            start.minute,
            start.second,
          );
        }
        final unit = switch (span[2]) {
          'ms' => 1,
          's' => 1000,
          'm' => 60000,
          'h' => 3600000,
          'd' => 86400000,
          _ => 604800000,
        };
        end ??= start!.add(Duration(milliseconds: (amount * unit).round()));
        // each day left out moves the end a day on
        if (excludes.isNotEmpty) {
          var at = start!.add(const Duration(days: 1));
          for (var extra = 0; !at.isAfter(end!) && extra < 10000;) {
            if (skipped(at)) {
              end = end.add(const Duration(days: 1));
              extra++;
            }
            at = at.add(const Duration(days: 1));
          }
        }
      }
      if (end == null || end.isBefore(start!)) return null;
      final made = GanttTask(
        name,
        start,
        end,
        id: id,
        section: section,
        done: tags.contains('done'),
        active: tags.contains('active'),
        critical: tags.contains('crit'),
        milestone: tags.contains('milestone'),
      );
      tasks[k] = made;
      if (id != null) byId[id] = made;
      progress = true;
    }
    if (!progress) break;
  }
  // a loop of "after"s can't be laid out
  if (tasks.contains(null)) return null;
  final made = tasks.nonNulls.toList();
  // the days left out, drawn as bands (not over more than 5 years, as
  // Mermaid)
  final excluded = <DateTime>[];
  if (excludes.isNotEmpty) {
    final first = made
        .map((t) => t.start)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final last = made.map((t) => t.end).reduce((a, b) => a.isAfter(b) ? a : b);
    if (last.difference(first).inDays <= 5 * 366) {
      for (
        var at = DateTime.utc(first.year, first.month, first.day);
        at.isBefore(last);
        at = DateTime.utc(at.year, at.month, at.day + 1)
      ) {
        if (skipped(at)) excluded.add(at);
      }
    }
  }
  return GanttChart(
    title,
    sections,
    made,
    axisFormat: axisFormat,
    excluded: excluded,
  );
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Writes [date] in a gantt chart's axisFormat: %Y %y %m %d %e %j %b %B
/// %a %A %H %I %p %M %S and %%; null when the format has another token.
String? formatGanttDate(DateTime date, String format) {
  String two(int n) => n.toString().padLeft(2, '0');
  final out = StringBuffer();
  for (var at = 0; at < format.length; at++) {
    if (format[at] != '%' || at + 1 == format.length) {
      out.write(format[at]);
      continue;
    }
    at++;
    final part = switch (format[at]) {
      'Y' => '${date.year}',
      'm' => two(date.month),
      'd' => two(date.day),
      'e' => '${date.day}',
      'b' => _monthNames[date.month - 1],
      'H' => two(date.hour),
      'M' => two(date.minute),
      'S' => two(date.second),
      'a' => _weekdays[date.weekday - 1].substring(0, 3).capitalized,
      'A' => _weekdays[date.weekday - 1].capitalized,
      'B' => _monthLong[date.month - 1],
      'y' => two(date.year % 100),
      'j' =>
        (date.difference(DateTime.utc(date.year)).inDays + 1)
            .toString()
            .padLeft(3, '0'),
      'I' => two((date.hour + 11) % 12 + 1),
      'p' => date.hour < 12 ? 'AM' : 'PM',
      '%' => '%',
      _ => null,
    };
    if (part == null) return null;
    out.write(part);
  }
  return out.toString();
}

// ---- mindmaps ---------------------------------------------------------

// (opener, closer, shape); longer openers first
const _mindShapes = [
  ('((', '))', MindShape.circle),
  ('))', '((', MindShape.bang),
  ('{{', '}}', MindShape.hexagon),
  (')', '(', MindShape.cloud),
  ('[', ']', MindShape.square),
  ('(', ')', MindShape.rounded),
];

MindNode _mindNode(String text) {
  final id = RegExp(r'^[^\s\[\](){}]*').firstMatch(text)![0]!;
  final rest = text.substring(id.length);
  for (final (open, close, shape) in _mindShapes) {
    if (rest.length >= open.length + close.length &&
        rest.startsWith(open) &&
        rest.endsWith(close)) {
      return MindNode(
        _mindText(rest.substring(open.length, rest.length - close.length)),
        shape,
      );
    }
  }
  return MindNode(_mindText(text));
}

// a "`markdown string`" is shown as its text
String _mindText(String raw) {
  final text = _label(raw);
  return text.length >= 2 && text.startsWith('`') && text.endsWith('`')
      ? text.substring(1, text.length - 1).trim()
      : text;
}

MindMap? _mindmap(Iterable<String> lines) {
  MindNode? root;
  final open = <(int, MindNode)>[];
  for (final line in lines) {
    final text = line.trim();
    // icons and classes change nothing drawn here
    if (text.startsWith('::icon(') || text.startsWith(':::')) continue;
    final indent = line
        .substring(0, line.length - line.trimLeft().length)
        .replaceAll('\t', '    ')
        .length;
    while (open.isNotEmpty && open.last.$1 >= indent) {
      open.removeLast();
    }
    final node = _mindNode(text);
    if (open.isEmpty) {
      // one root only
      if (root != null) return null;
      root = node;
    } else {
      open.last.$2.children.add(node);
    }
    open.add((indent, node));
  }
  return root == null ? null : MindMap(root);
}

// ---- timelines --------------------------------------------------------

Timeline? _timeline(Iterable<String> lines) {
  String? title;
  String? section;
  final periods = <TimelinePeriod>[];
  for (final line in lines) {
    final word = RegExp(
      r'^(title|section|accTitle|accDescr)\b\s*:?\s*(.*)$',
    ).firstMatch(line);
    if (word != null) {
      switch (word[1]) {
        case 'title':
          title = _label(word[2]!);
        case 'section':
          section = _label(word[2]!);
      }
      continue;
    }
    // Events follow a colon with a space after it, as in Mermaid's grammar,
    // so "10:30" stays whole (Mermaid itself refuses a colon in a period;
    // here it is kept).
    final parts = line
        .split(RegExp(r':(?=\s|$)'))
        .map((part) => _label(part))
        .toList();
    if (parts.first.isEmpty) {
      // ": event" goes on with the period above
      if (periods.isEmpty) return null;
    } else {
      periods.add(TimelinePeriod(parts.first, section: section));
    }
    periods.last.events.addAll(parts.skip(1).where((e) => e.isNotEmpty));
  }
  if (periods.isEmpty) return null;
  return Timeline(title, periods);
}

// ---- colors and styling -----------------------------------------------

const _cssColors = {
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
  'aqua': 0xFF00FFFF,
  'magenta': 0xFFFF00FF,
  'brown': 0xFFA52A2A,
  'teal': 0xFF008080,
  'navy': 0xFF000080,
  'lime': 0xFF00FF00,
  'gold': 0xFFFFD700,
  'silver': 0xFFC0C0C0,
  'lightgray': 0xFFD3D3D3,
  'lightgrey': 0xFFD3D3D3,
  'darkgray': 0xFFA9A9A9,
  'darkgrey': 0xFFA9A9A9,
  'lightblue': 0xFFADD8E6,
  'lightgreen': 0xFF90EE90,
  'lightyellow': 0xFFFFFFE0,
  'darkblue': 0xFF00008B,
  'darkgreen': 0xFF006400,
  'darkred': 0xFF8B0000,
  'transparent': 0x00000000,
  'none': 0x00000000,
};

final RegExp _hexColor = RegExp(r'^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$');

/// Reads a CSS color written as #rgb, #rgba, #rrggbb, #rrggbbaa or one of
/// the common names, as 0xAARRGGBB; null for anything else.
int? parseCssColor(String text) {
  final value = text.trim().toLowerCase();
  final named = _cssColors[value];
  if (named != null) return named;
  var hex = _hexColor.firstMatch(value)?[1];
  if (hex == null) return null;
  if (hex.length <= 4) {
    hex = [for (final digit in hex.split('')) '$digit$digit'].join();
  }
  final rgb = int.parse(hex.substring(0, 6), radix: 16);
  final alpha = hex.length == 8 ? int.parse(hex.substring(6), radix: 16) : 255;
  return alpha << 24 | rgb;
}

final RegExp _cssNumber = RegExp(r'^(\d+(?:\.\d+)?|\.\d+)(?:px)?$');

// "fill:#f9f,stroke:#333,stroke-width:2px"; properties and values it
// doesn't know are left out, and it is null when nothing is left.
FlowStyle? _flowStyle(String text) {
  int? fill;
  int? stroke;
  int? color;
  double? strokeWidth;
  bool? dashed;
  for (final part in text.split(',')) {
    final colon = part.indexOf(':');
    if (colon == -1) continue;
    // "interpolate basis stroke:#f00": the property is the last word
    final property = part
        .substring(0, colon)
        .trim()
        .split(RegExp(r'\s+'))
        .last
        .toLowerCase();
    final value = part
        .substring(colon + 1)
        .replaceAll('!important', '')
        .replaceAll(';', '')
        .trim()
        .toLowerCase();
    switch (property) {
      case 'fill':
        fill = parseCssColor(value) ?? fill;
      case 'stroke':
        stroke = parseCssColor(value) ?? stroke;
      case 'color':
        color = parseCssColor(value) ?? color;
      case 'stroke-width':
        final number = _cssNumber.firstMatch(value)?[1];
        if (number != null) {
          strokeWidth = math.min(double.parse(number), 12);
        }
      case 'stroke-dasharray':
        dashed = value.isNotEmpty && value != 'none' && value != '0';
    }
  }
  final style = FlowStyle(
    fill: fill,
    stroke: stroke,
    color: color,
    strokeWidth: strokeWidth,
    dashed: dashed,
  );
  return style.isEmpty ? null : style;
}

const _styledId = r'[\w\u0080-￿.-]+';
final RegExp _classDefLine = RegExp(
  r'^classDef\s+([\w-]+(?:\s*,\s*[\w-]+)*)\s+(.+)$',
);
final RegExp _classLine = RegExp(
  '^(class|cssClass)\\s+"?($_styledId(?:\\s*,\\s*$_styledId)*)"?\\s+([\\w-]+)\$',
);
final RegExp _styleLine = RegExp(
  '^style\\s+($_styledId(?:\\s*,\\s*$_styledId)*)\\s+(.*:.*)\$',
);
final RegExp _linkStyleLine = RegExp(
  r'^linkStyle\s+(default|\d+(?:\s*,\s*\d+)*)\s+(.*:.*)$',
);
final RegExp _classTag = RegExp('($_styledId):::([\\w-]+)');

// What classDef, class, ":::", style and linkStyle lines say, kept until
// the whole diagram is read: a class may be used before it is defined.
class _Styling {
  final _defs = <String, FlowStyle>{};
  final _classes = <String, List<String>>{};
  final _direct = <String, FlowStyle>{};
  final _links = <int, FlowStyle>{};
  FlowStyle? _defaultLink;

  void tag(String id, String name) =>
      _classes.putIfAbsent(id, () => []).add(name);

  // "A:::name" is read as "A", and the class kept
  String untag(String line) => line.replaceAllMapped(_classTag, (match) {
    tag(match[1]!, match[2]!);
    return match[1]!;
  });

  // Whether [line] was a styling line. "class A,B name" is one only where
  // [classLines] is set: in a class diagram "class" starts a class.
  bool read(String line, {bool classLines = true}) {
    final def = _classDefLine.firstMatch(line);
    if (def != null) {
      final style = _flowStyle(def[2]!);
      if (style != null) {
        for (final name in def[1]!.split(',')) {
          final key = name.trim();
          _defs[key] = _defs[key]?.merge(style) ?? style;
        }
      }
      return true;
    }
    final use = _classLine.firstMatch(line);
    if (use != null && (classLines || use[1] == 'cssClass')) {
      for (final id in use[2]!.split(',')) {
        tag(id.trim(), use[3]!);
      }
      return true;
    }
    final direct = _styleLine.firstMatch(line);
    if (direct != null) {
      final style = _flowStyle(direct[2]!);
      if (style != null) {
        for (final id in direct[1]!.split(',')) {
          final key = id.trim();
          _direct[key] = _direct[key]?.merge(style) ?? style;
        }
      }
      return true;
    }
    final link = _linkStyleLine.firstMatch(line);
    if (link != null) {
      final style = _flowStyle(link[2]!);
      if (style == null) return true;
      if (link[1] == 'default') {
        _defaultLink = _defaultLink?.merge(style) ?? style;
      } else {
        for (final number in link[1]!.split(',')) {
          final index = int.tryParse(number.trim());
          if (index == null) continue;
          _links[index] = _links[index]?.merge(style) ?? style;
        }
      }
      return true;
    }
    return false;
  }

  // The class "default" first, then the node's classes in the order they
  // were given, then its own style line.
  void apply(Iterable<FlowNode> nodes) {
    for (final node in nodes) {
      var style = _defs['default'];
      for (final name in _classes[node.id] ?? const <String>[]) {
        final next = _defs[name];
        if (next != null) style = style?.merge(next) ?? next;
      }
      final own = _direct[node.id];
      if (own != null) style = style?.merge(own) ?? own;
      node.style = style;
    }
  }

  void applyLinks(List<FlowEdge> edges) {
    for (var i = 0; i < edges.length; i++) {
      var style = _defaultLink;
      final own = _links[i];
      if (own != null) style = style?.merge(own) ?? own;
      if (style != null) edges[i] = edges[i].styled(style);
    }
  }
}

// a number a drawing can be scaled by: finite and not huge
double? _number(String text) {
  final value = double.tryParse(text.trim());
  return value == null || !value.isFinite || value.abs() > 1e12 ? null : value;
}

// ---- git graphs -------------------------------------------------------

final RegExp _gitLine = RegExp(
  r'^(commit|branch|checkout|switch|merge|cherry-pick)(?:\s+(.*))?$',
);
final RegExp _gitAttribute = RegExp(
  r'\b(id|tag|type|msg|order|parent)\s*:\s*(?:"([^"]*)"|(\S+))',
);
final RegExp _gitName = RegExp(r'^(?:"([^"]+)"|([^\s:"]+))(?=\s|$)');

GitGraph? _gitGraph(Iterable<String> lines) {
  final branches = <String>['main'];
  // the last commit of each branch
  final heads = <int?>[null];
  final commits = <GitCommit>[];
  var current = 0;

  void add(String rest, {int? other, String? tag}) {
    String? label;
    final tags = <String>[];
    if (tag != null) tags.add(tag);
    var type = GitCommitType.normal;
    for (final match in _gitAttribute.allMatches(rest)) {
      final value = match[2] ?? match[3]!;
      switch (match[1]) {
        case 'id':
          // a cherry-pick's id is the commit it copies, not its own
          if (tag == null && value.isNotEmpty) label = value;
        case 'tag':
          if (value.isNotEmpty) tags.add(value);
        case 'type':
          type = switch (value.toUpperCase()) {
            'REVERSE' => GitCommitType.reverse,
            'HIGHLIGHT' => GitCommitType.highlight,
            _ => GitCommitType.normal,
          };
      }
    }
    final head = heads[current];
    commits.add(
      GitCommit(
        current,
        parents: [head, other].nonNulls.toList(),
        label: label,
        tag: tags.isEmpty ? null : tags.join(', '),
        type: type,
        merge: other != null,
      ),
    );
    heads[current] = commits.length - 1;
  }

  for (final line in lines) {
    final match = _gitLine.firstMatch(line);
    if (match == null) continue;
    final rest = (match[2] ?? '').trim();
    final named = _gitName.firstMatch(rest);
    final name = named?[1] ?? named?[2];
    switch (match[1]) {
      case 'commit':
        add(rest);
      case 'cherry-pick':
        final picked = _gitAttribute
            .allMatches(rest)
            .where((m) => m[1] == 'id')
            .firstOrNull;
        final id = picked?[2] ?? picked?[3];
        if (id != null && id.isNotEmpty) add(rest, tag: 'cherry-pick: $id');
      case 'branch':
        if (name == null) continue;
        final at = branches.indexOf(name);
        if (at != -1) {
          current = at;
        } else {
          branches.add(name);
          heads.add(heads[current]);
          current = branches.length - 1;
        }
      case 'checkout' || 'switch':
        final at = name == null ? -1 : branches.indexOf(name);
        if (at != -1) current = at;
      case 'merge':
        final at = name == null ? -1 : branches.indexOf(name);
        final other = at == -1 || at == current ? null : heads[at];
        if (other == null || other == heads[current]) continue;
        add(rest.substring(named!.end), other: other);
    }
  }
  if (commits.isEmpty) return null;
  return GitGraph(branches, commits);
}

// ---- user journeys ----------------------------------------------------

final RegExp _journeyTask = RegExp(
  r'^([^:]+?)\s*:\s*(-?\d{1,9})\s*(?::\s*(.*))?$',
);
final RegExp _titled = RegExp(r'^(title|section)(?:\s+(.*))?$');

Journey? _journey(Iterable<String> lines) {
  String? title;
  String? section;
  final tasks = <JourneyTask>[];
  for (final line in lines) {
    final word = _titled.firstMatch(line);
    if (word != null) {
      final text = _label(word[2] ?? '');
      if (word[1] == 'title') {
        title = text.isEmpty ? null : text;
      } else {
        section = text.isEmpty ? null : text;
      }
      continue;
    }
    final task = _journeyTask.firstMatch(line);
    if (task == null) continue;
    tasks.add(
      JourneyTask(
        _label(task[1]!),
        int.parse(task[2]!).clamp(1, 5),
        actors: [
          for (final actor in (task[3] ?? '').split(','))
            if (actor.trim().isNotEmpty) actor.trim(),
        ],
        section: section,
      ),
    );
  }
  if (tasks.isEmpty) return null;
  return Journey(title, tasks);
}

// ---- quadrant charts --------------------------------------------------

final RegExp _axisLine = RegExp(r'^([xy])-axis\s+(.+)$');
final RegExp _quadrantName = RegExp(r'^quadrant-([1-4])\s+(.+)$');
final RegExp _quadrantPoint = RegExp(
  r'^(.+?)(?::::[\w-]+)?\s*:\s*\[\s*([^,\]\s]+)\s*,\s*([^,\]\s]+)\s*\]',
);

QuadrantChart? _quadrant(Iterable<String> lines) {
  String? title;
  final axes = <String, (String?, String?)>{};
  final quadrants = List<String?>.filled(4, null);
  final points = <QuadrantPoint>[];
  for (final line in lines) {
    final word = _titled.firstMatch(line);
    if (word != null && word[1] == 'title') {
      final text = _label(word[2] ?? '');
      title = text.isEmpty ? null : text;
      continue;
    }
    final axis = _axisLine.firstMatch(line);
    if (axis != null) {
      final ends = axis[2]!.split('-->');
      String? end(int k) {
        final text = k < ends.length ? _label(ends[k]) : '';
        return text.isEmpty ? null : text;
      }

      axes[axis[1]!] = (end(0), end(1));
      continue;
    }
    final quadrant = _quadrantName.firstMatch(line);
    if (quadrant != null) {
      quadrants[int.parse(quadrant[1]!) - 1] = _label(quadrant[2]!);
      continue;
    }
    final point = _quadrantPoint.firstMatch(line);
    if (point == null) continue;
    final x = _number(point[2]!);
    final y = _number(point[3]!);
    if (x == null || y == null) continue;
    points.add(
      QuadrantPoint(_label(point[1]!), x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)),
    );
  }
  if (points.isEmpty && quadrants.every((name) => name == null)) return null;
  return QuadrantChart(
    title,
    quadrants,
    points,
    xLow: axes['x']?.$1,
    xHigh: axes['x']?.$2,
    yLow: axes['y']?.$1,
    yHigh: axes['y']?.$2,
  );
}

// ---- sankey diagrams --------------------------------------------------

// One CSV row: fields between commas; a field in double quotes may hold
// commas, and "" inside it is a quote. Null for a quote left open.
List<String>? _csvFields(String row) {
  final fields = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var at = 0; at < row.length; at++) {
    final char = row[at];
    if (quoted) {
      if (char != '"') {
        field.write(char);
      } else if (at + 1 < row.length && row[at + 1] == '"') {
        field.write('"');
        at++;
      } else {
        quoted = false;
      }
    } else if (char == '"' && field.toString().trim().isEmpty) {
      field.clear();
      quoted = true;
    } else if (char == ',') {
      fields.add(field.toString().trim());
      field.clear();
    } else {
      field.write(char);
    }
  }
  if (quoted) return null;
  fields.add(field.toString().trim());
  return fields;
}

Sankey? _sankey(Iterable<String> lines) {
  final nodes = <String>[];
  final links = <SankeyLink>[];
  int node(String name) {
    final at = nodes.indexOf(name);
    if (at != -1) return at;
    nodes.add(name);
    return nodes.length - 1;
  }

  for (final line in lines) {
    final fields = _csvFields(line);
    if (fields == null || fields.length != 3) continue;
    final value = _number(fields[2]);
    if (value == null || value <= 0) continue;
    if (fields[0].isEmpty || fields[1].isEmpty || fields[0] == fields[1]) {
      continue;
    }
    links.add(SankeyLink(node(fields[0]), node(fields[1]), value));
  }
  if (links.isEmpty) return null;
  return Sankey(nodes, links);
}

// ---- xy charts --------------------------------------------------------

final RegExp _xyRange = RegExp(r'^(.*?)\s*(-?[\d.]+)\s*-->\s*(-?[\d.]+)$');
final RegExp _xySeries = RegExp(r'^(bar|line)\b[^\[]*\[([^\]]*)\]$');

XyChart? _xyChart(Iterable<String> lines) {
  String? title;
  String? xTitle;
  String? yTitle;
  List<String>? categories;
  (double, double)? xRange;
  (double, double)? yRange;
  final series = <XySeries>[];
  String? named(String raw) {
    final text = _label(raw);
    return text.isEmpty ? null : text;
  }

  for (final line in lines) {
    final word = _titled.firstMatch(line);
    if (word != null && word[1] == 'title') {
      title = named(word[2] ?? '');
      continue;
    }
    final axis = _axisLine.firstMatch(line);
    if (axis != null) {
      final rest = axis[2]!.trim();
      final x = axis[1] == 'x';
      final open = rest.indexOf('[');
      final range = _xyRange.firstMatch(rest);
      final low = range == null ? null : _number(range[2]!);
      final high = range == null ? null : _number(range[3]!);
      String? name;
      if (x && open != -1 && rest.endsWith(']')) {
        final fields = _csvFields(rest.substring(open + 1, rest.length - 1));
        if (fields == null) continue;
        categories = [
          for (final field in fields)
            if (field.isNotEmpty) field,
        ];
        name = named(rest.substring(0, open));
      } else if (low != null && high != null && low != high) {
        final ends = (math.min(low, high), math.max(low, high));
        if (x) {
          xRange = ends;
          categories = null;
        } else {
          yRange = ends;
        }
        name = named(range![1]!);
      } else {
        name = named(rest);
      }
      if (x) {
        xTitle = name;
      } else {
        yTitle = name;
      }
      continue;
    }
    final data = _xySeries.firstMatch(line);
    if (data == null) continue;
    final values = [for (final value in data[2]!.split(',')) _number(value)];
    // one unreadable value would shift the rest, so the line is left out
    if (values.contains(null)) continue;
    series.add(XySeries(values.nonNulls.toList(), bar: data[1] == 'bar'));
  }
  if (series.isEmpty) return null;
  return XyChart(
    series,
    title: title,
    xTitle: xTitle,
    yTitle: yTitle,
    categories: categories == null || categories.isEmpty ? null : categories,
    xRange: xRange,
    yRange: yRange,
  );
}

extension on String {
  String get capitalized => '${this[0].toUpperCase()}${substring(1)}';
}
