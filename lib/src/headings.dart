import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

/// A heading of the reply, for a table of contents.
@immutable
class MarkdownHeading {
  /// Creates a heading.
  const MarkdownHeading(this.level, this.text, this.id);

  /// 1 for `#`, up to 6 for `######`.
  final int level;

  /// The heading's text, without Markdown.
  final String text;

  /// The id that `[link](#id)` and [MarkdownHeadings.scrollTo] use, made the
  /// way GitHub makes them: `## Getting started` becomes `getting-started`,
  /// and a second heading with the same text gets `-1` added.
  final String id;

  @override
  bool operator ==(Object other) =>
      other is MarkdownHeading &&
      other.level == level &&
      other.text == text &&
      other.id == id;

  @override
  int get hashCode => Object.hash(level, text, id);

  @override
  String toString() => 'MarkdownHeading($level, $text, #$id)';
}

/// The headings of a `StreamingMarkdown`, for a table of contents.
///
/// Pass it as `StreamingMarkdown.headings`; it notifies its listeners when
/// a heading is added or changes.
class MarkdownHeadings extends ChangeNotifier {
  List<MarkdownHeading> _headings = const [];
  Map<String, GlobalKey>? _anchors;

  /// The headings in reading order.
  List<MarkdownHeading> get headings => _headings;

  /// Scrolls the heading with [id] into view. Returns false when it isn't
  /// on screen or in a lazily built list part that hasn't been built yet.
  Future<bool> scrollTo(
    String id, {
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOut,
  }) async {
    final context = _anchors?[headingAnchor(id)]?.currentContext;
    if (context == null || !context.mounted) return false;
    await Scrollable.ensureVisible(context, duration: duration, curve: curve);
    return true;
  }

  // ignore: use_setters_to_change_properties
  void attach(Map<String, GlobalKey> anchors) => _anchors = anchors;

  void detach(Map<String, GlobalKey> anchors) {
    if (identical(_anchors, anchors)) _anchors = null;
  }

  void update(List<MarkdownHeading> headings) {
    if (listEquals(headings, _headings)) return;
    _headings = List.unmodifiable(headings);
    // the list changes while the widget builds
    scheduleMicrotask(notifyListeners);
  }
}

/// The anchors key of a heading, apart from footnote ids such as `fn-1`.
String headingAnchor(String id) => 'h:$id';

final RegExp _notSlug = RegExp(r'[^\p{L}\p{N}\- ]', unicode: true);

/// GitHub's heading id: lower case, punctuation dropped, spaces to dashes.
String headingSlug(String text) =>
    text.trim().toLowerCase().replaceAll(_notSlug, '').replaceAll(' ', '-');

/// Gives every heading in [nodes] an `id`, counting [used] ids so repeated
/// headings get `-1`, `-2`. Returns the headings found.
List<MarkdownHeading> assignHeadingIds(
  List<md.Node> nodes,
  Map<String, int> used,
) {
  final found = <MarkdownHeading>[];
  void walk(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is! md.Element) continue;
      final tag = node.tag;
      if (tag.length == 2 && tag.startsWith('h')) {
        final level = int.tryParse(tag.substring(1));
        if (level != null && level >= 1 && level <= 6) {
          final text = node.textContent.trim();
          final base = headingSlug(text);
          // "a", "a-1", ... and never an id given before, so two headings
          // can't share an anchor
          var id = base;
          var count = used[base];
          if (count == null) {
            used[base] = 0;
          } else {
            do {
              count = count! + 1;
              id = '$base-$count';
            } while (used.containsKey(id));
            used[base] = count;
          }
          used.putIfAbsent(id, () => 0);
          node.attributes['id'] = id;
          found.add(MarkdownHeading(level, text, id));
          continue;
        }
      }
      if (tag == 'ul' || tag == 'ol' || tag == 'li' || tag == 'blockquote') {
        walk(node.children ?? const []);
      }
    }
  }

  walk(nodes);
  return found;
}
