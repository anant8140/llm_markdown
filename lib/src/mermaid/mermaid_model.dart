// A small reader for the Mermaid diagrams that chat models write most:
// flowcharts, sequence diagrams and pie charts. Anything else returns null
// and is shown as code.

sealed class MermaidData {
  const MermaidData();
}

enum FlowDirection { down, up, right, left }

enum NodeShape { rect, rounded, stadium, circle, diamond, hexagon }

enum EdgeLine { solid, dotted, thick }

class FlowNode {
  FlowNode(this.id) : label = id;

  final String id;
  String label;
  NodeShape shape = NodeShape.rect;
}

class FlowEdge {
  const FlowEdge(
    this.from,
    this.to, {
    this.label,
    this.line = EdgeLine.solid,
    this.arrow = true,
  });

  final String from;
  final String to;
  final String? label;
  final EdgeLine line;
  final bool arrow;
}

class FlowChart extends MermaidData {
  const FlowChart(this.direction, this.nodes, this.edges);

  final FlowDirection direction;
  final List<FlowNode> nodes;
  final List<FlowEdge> edges;
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

final RegExp _comment = RegExp(r'%%.*$', multiLine: true);
final RegExp _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);

/// Reads [source], or returns null when it isn't a diagram this package
/// draws.
MermaidData? parseMermaid(String source) {
  final lines = source
      .replaceAll(_comment, '')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  // an optional "---\ntitle: x\n---" block comes first
  if (lines.isNotEmpty && lines.first == '---') {
    final end = lines.indexOf('---', 1);
    if (end == -1) return null;
    lines.removeRange(0, end + 1);
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
  if (RegExp(r'^sequenceDiagram\b').hasMatch(head)) {
    return _sequence(lines.skip(1));
  }
  if (RegExp(r'^pie\b').hasMatch(head)) return _pie(lines);
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

FlowChart? _flowChart(String? direction, List<String> lines) {
  final nodes = <String, FlowNode>{};
  final edges = <FlowEdge>[];

  for (final line in lines) {
    for (final statement in line.split(';')) {
      final text = statement.trim();
      if (text.isEmpty) continue;
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
          final node = nodes.putIfAbsent(id[0]!, () => FlowNode(id[0]!));
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
          final styled = RegExp(r':::[\w-]+').matchAsPrefix(text, at);
          if (styled != null) at = styled.end;
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
                arrow: arrow,
              ),
            );
          }
        }
        from = to;
      }
    }
  }
  if (nodes.isEmpty) return null;
  return FlowChart(
    switch (direction?.toUpperCase()) {
      'BT' => FlowDirection.up,
      'LR' => FlowDirection.right,
      'RL' => FlowDirection.left,
      _ => FlowDirection.down,
    },
    nodes.values.toList(),
    edges,
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
