// Finds the places where streamed Markdown can be cut into blocks that parse
// the same way whatever text arrives after them.
//
// A cut is only reported when it is certain. Anything that a later character
// could still change stays in the open block, which is parsed again on every
// update. Being too careful only costs time; cutting too early would show
// the wrong result, so every rule here errs towards not cutting.

final RegExp _listMarker = RegExp(r'^ {0,3}(?:[-+*]|\d{1,9}[.)])(?:[ \t]|$)');
final RegExp _partialListMarker = RegExp(r'^ {0,3}(?:[-+*]|\d{1,9}[.)]?)$');
final RegExp _footnoteDefinition = RegExp(r'^ {0,3}\[\^[^\]]+\]:');
final RegExp _fenceOpener = RegExp(r'^( {0,3})(`{3,}|~{3,})(.*)$');
final RegExp _fenceCloser = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*$');
final RegExp _atxHeading = RegExp(r'^ {0,3}#{1,6}([ \t]|$)');
final RegExp _htmlRawBlock = RegExp(
  r'^ {0,3}<(?:(script|pre|style|textarea)(?=[\s>]|$)|(!--)|(\?)|(![A-Za-z])|(!\[CDATA\[))',
  caseSensitive: false,
);
final RegExp _htmlRawTagEnd = RegExp(
  r'</(?:script|pre|style|textarea)>',
  caseSensitive: false,
);

/// A fenced code block that has been opened and not yet closed.
class OpenFence {
  /// Creates an open fence with its indentation and fence characters.
  const OpenFence(this.indent, this.marker);

  /// The spaces before the opening fence.
  final String indent;

  /// The fence characters, such as ```` ``` ```` or `~~~~`.
  final String marker;

  /// The fence character, a backtick or a tilde.
  String get char => marker[0];

  /// Whether [line] closes this fence.
  bool isClosedBy(String line) {
    final match = _fenceCloser.firstMatch(line);
    if (match == null) return false;
    final closing = match[1]!;
    return closing[0] == char && closing.length >= marker.length;
  }
}

/// Returns the fence that [line] opens, or null when it opens none.
OpenFence? fenceOpenedBy(String line) {
  final match = _fenceOpener.firstMatch(line);
  if (match == null) return null;
  final marker = match[2]!;
  if (marker[0] == '`' && match[3]!.contains('`')) return null;
  return OpenFence(match[1]!, marker);
}

/// Removes a trailing carriage return, so CRLF text is handled like LF text.
String withoutCarriageReturn(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

int _indentWidth(String line) {
  var width = 0;
  for (var i = 0; i < line.length; i++) {
    final unit = line.codeUnitAt(i);
    if (unit == 0x20) {
      width++;
    } else if (unit == 0x09) {
      width += 4 - width % 4;
    } else {
      break;
    }
  }
  return width;
}

RegExp _htmlEndFor(RegExpMatch start) {
  if (start[1] != null) return _htmlRawTagEnd;
  if (start[2] != null) return RegExp('-->');
  if (start[3] != null) return RegExp(r'\?>');
  if (start[4] != null) return RegExp('>');
  return RegExp(r'\]\]>');
}

/// Returns the offsets in [text], after [start], where a new independent
/// block begins.
///
/// The text from [start] to the first offset, and between two offsets, can
/// be parsed on its own and will never need to be parsed again. When
/// [complete] is false the last line may still grow, so decisions that
/// depend on it are postponed.
List<int> findBlockBoundaries(
  String text,
  int start, {
  required bool complete,
}) {
  final boundaries = <int>[];
  var pos = start;
  var hasContent = false;
  // Whether the current block holds something that a later indented line or
  // list item could still continue: a list, a footnote or indented code.
  var continuable = false;
  var afterBlank = false;
  OpenFence? fence;
  RegExp? htmlEnd;

  void startBlockAt(int offset) {
    if (offset > start && (boundaries.isEmpty || offset > boundaries.last)) {
      boundaries.add(offset);
    }
    hasContent = false;
    continuable = false;
    afterBlank = false;
  }

  while (pos < text.length) {
    final newline = text.indexOf('\n', pos);
    final hasNewline = newline != -1;
    final next = hasNewline ? newline + 1 : text.length;
    final line = withoutCarriageReturn(
      text.substring(pos, hasNewline ? newline : text.length),
    );
    final lineComplete = hasNewline || complete;

    if (fence != null) {
      if (lineComplete && fence.isClosedBy(line)) {
        fence = null;
        startBlockAt(next);
      }
      pos = next;
      continue;
    }

    if (htmlEnd != null) {
      if (htmlEnd.hasMatch(line)) htmlEnd = null;
      pos = next;
      continue;
    }

    if (line.trim().isEmpty) {
      // A partial line of spaces is the last line, so no cut can follow it
      // in this update; treating it as blank is safe.
      if (hasContent) afterBlank = true;
      pos = next;
      continue;
    }

    final indent = _indentWidth(line);

    if (afterBlank) {
      if (!continuable) {
        startBlockAt(pos);
      } else if (indent > 0 ||
          _listMarker.hasMatch(line) ||
          _footnoteDefinition.hasMatch(line)) {
        // The list, footnote or indented code continues.
        afterBlank = false;
      } else if (!lineComplete && _partialListMarker.hasMatch(line)) {
        break;
      } else {
        startBlockAt(pos);
      }
    }

    // Inside a list, an indented fence or heading belongs to a list item.
    final nested = continuable && indent > 0;

    if (indent <= 3 && !nested) {
      final opener = _fenceOpener.firstMatch(line);
      if (opener != null) {
        // A backtick fence is only a fence if its info string has no
        // backtick, which the rest of the line could still add.
        if (opener[2]![0] == '`' && !lineComplete) break;
        final opened = fenceOpenedBy(line);
        if (opened != null) {
          if (hasContent) startBlockAt(pos);
          fence = opened;
          hasContent = true;
          pos = next;
          continue;
        }
      }

      final heading = _atxHeading.firstMatch(line);
      // "#" alone may still become "#tag", which is not a heading.
      if (heading != null && (heading[1]!.isNotEmpty || lineComplete)) {
        if (hasContent) startBlockAt(pos);
        if (hasNewline) {
          startBlockAt(next);
        } else {
          hasContent = true;
        }
        pos = next;
        continue;
      }

      final html = _htmlRawBlock.firstMatch(line);
      if (html != null) {
        final end = _htmlEndFor(html);
        if (!end.hasMatch(line.substring(html.end))) htmlEnd = end;
        hasContent = true;
        pos = next;
        continue;
      }
    }

    if (indent >= 4 ||
        _listMarker.hasMatch(line) ||
        _footnoteDefinition.hasMatch(line)) {
      continuable = true;
    }
    hasContent = true;
    pos = next;
  }

  return boundaries;
}
