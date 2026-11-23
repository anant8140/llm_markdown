import 'package:flutter/foundation.dart';

/// Every piece of text the widgets show or read out by themselves, so an
/// app can translate or reword it.
///
/// ```dart
/// StreamingMarkdown(
///   controller: controller,
///   labels: const MarkdownLabels(
///     copy: 'Kopieren',
///     showCode: 'Code zeigen',
///     alertTitles: {'note': 'Hinweis', 'tip': 'Tipp'},
///   ),
/// )
/// ```
///
/// The title of the thinking section comes from
/// `StreamingMarkdown.thinkingLabel`, and the menu of a
/// `MarkdownSelectionArea` has its own labels.
@immutable
class MarkdownLabels {
  /// Creates a set of labels; what is left out stays English.
  const MarkdownLabels({
    this.copy,
    this.showAllLines,
    this.showLess = 'Show less',
    this.showCode = 'Show code',
    this.showDiagram = 'Show diagram',
    this.closeImage = 'Close image',
    this.details = 'Details',
    this.alertTitles = const {},
    this.spoilerHint = 'Spoiler, tap to show',
    this.citation,
    this.toolCall,
  });

  /// The copy button of a code block. Null uses the platform's own word for
  /// "Copy" in the app's language, or "Copy".
  final String? copy;

  /// The button that opens a collapsed code block, given its number of
  /// lines; defaults to "Show all N lines".
  final String Function(int lines)? showAllLines;

  /// The button that collapses a code block again.
  final String showLess;

  /// Under a drawn diagram: switches to its source.
  final String showCode;

  /// Under a diagram's source: switches back to the drawing.
  final String showDiagram;

  /// Read out for the full screen image; a tap closes it.
  final String closeImage;

  /// The title of a `<details>` section that has no `<summary>`.
  final String details;

  /// Titles of GitHub alerts by type: `note`, `tip`, `important`, `warning`
  /// and `caution`. Types left out keep their English title.
  final Map<String, String> alertTitles;

  /// Read out for a hidden `||spoiler||`.
  final String spoilerHint;

  /// Read out for a citation chip, given its number; defaults to
  /// "Source N".
  final String Function(int number)? citation;

  /// The line shown for a tool call, given the tool's name and whether it
  /// has finished; defaults to "Using web search…" and "Used web search".
  final String Function(String name, bool done)? toolCall;

  @override
  bool operator ==(Object other) =>
      other is MarkdownLabels &&
      other.copy == copy &&
      other.showAllLines == showAllLines &&
      other.showLess == showLess &&
      other.showCode == showCode &&
      other.showDiagram == showDiagram &&
      other.closeImage == closeImage &&
      other.details == details &&
      mapEquals(other.alertTitles, alertTitles) &&
      other.spoilerHint == spoilerHint &&
      other.citation == citation &&
      other.toolCall == toolCall;

  @override
  int get hashCode => Object.hash(
    copy,
    showAllLines,
    showLess,
    showCode,
    showDiagram,
    closeImage,
    details,
    Object.hashAllUnordered(alertTitles.entries.map((e) => (e.key, e.value))),
    spoilerHint,
    citation,
    toolCall,
  );
}
