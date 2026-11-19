// Splits streamed markdown into blocks that can't change any more.
// When unsure, don't cut. A missed cut costs a re-parse, a wrong one shows
// the wrong output.

import 'math.dart';
import 'syntaxes.dart';

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
// <div> and friends run until a blank line, headings inside included.
final RegExp _htmlBlock = RegExp(
  r'^ {0,3}</?[A-Za-z][A-Za-z0-9-]*(?:[\s/>]|$)',
);
final RegExp _htmlRawTagEnd = RegExp(
  r'</(?:script|pre|style|textarea)>',
  caseSensitive: false,
);

class OpenFence {
  const OpenFence(this.indent, this.marker);

  final String indent;

  final String marker;

  String get char => marker[0];

  bool isClosedBy(String line) {
    final match = _fenceCloser.firstMatch(line);
    if (match == null) return false;
    final closing = match[1]!;
    return closing[0] == char && closing.length >= marker.length;
  }
}

OpenFence? fenceOpenedBy(String line) {
  final match = _fenceOpener.firstMatch(line);
  if (match == null) return null;
  final marker = match[2]!;
  if (marker[0] == '`' && match[3]!.contains('`')) return null;
  return OpenFence(match[1]!, marker);
}

bool isBlank(String text) => _blank.hasMatch(text);

final RegExp _blank = RegExp(r'^[ \t\r\n]*$');

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

List<int> findBlockBoundaries(
  String text,
  int start, {
  required bool complete,
  bool dollarMath = true,
}) {
  final mathOpener = mathOpenerFor(dollar: dollarMath);
  final boundaries = <int>[];
  var pos = start;
  var hasContent = false;
  // list / footnote / indented code: an indented line after a blank line
  // still belongs to it.
  var continuable = false;
  var afterBlank = false;
  var inHtmlBlock = false;
  OpenFence? fence;
  RegExp? mathEnd;
  RegExp? htmlEnd;
  var details = 0;
  // set after <!-- ... --> and friends end: a directly following HTML line
  // joins the same block in the markdown package
  var htmlChain = false;

  void startBlockAt(int offset) {
    if (offset > start && (boundaries.isEmpty || offset > boundaries.last)) {
      boundaries.add(offset);
    }
    hasContent = false;
    continuable = false;
    afterBlank = false;
    inHtmlBlock = false;
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

    if (mathEnd != null) {
      if (lineComplete && mathEnd.hasMatch(line)) {
        mathEnd = null;
        startBlockAt(next);
      }
      pos = next;
      continue;
    }

    // <details> can hold blank lines; it ends at its closing tag
    if (htmlChain) {
      htmlChain = false;
      final raw = _htmlRawBlock.firstMatch(line);
      if (raw != null) {
        final end = _htmlEndFor(raw);
        if (end.hasMatch(line.substring(raw.end))) {
          htmlChain = true;
        } else {
          htmlEnd = end;
        }
        pos = next;
        continue;
      }
      if (_htmlBlock.hasMatch(line)) {
        inHtmlBlock = true;
        pos = next;
        continue;
      }
    }

    final startsDetails =
        !inHtmlBlock &&
        !(continuable && _indentWidth(line) > 0) &&
        _shallow(line) &&
        detailsOpener.hasMatch(line);
    if (details > 0 || startsDetails) {
      if (detailsOpener.hasMatch(line)) {
        if (details == 0 && hasContent) startBlockAt(pos);
        details++;
      }
      if (detailsCloser.hasMatch(line)) details--;
      hasContent = true;
      if (details == 0 && lineComplete && hasNewline) startBlockAt(next);
      pos = next;
      continue;
    }

    if (htmlEnd != null) {
      if (htmlEnd.hasMatch(line)) {
        htmlEnd = null;
        htmlChain = true;
      }
      pos = next;
      continue;
    }

    if (isBlank(line)) {
      if (hasContent) afterBlank = true;
      inHtmlBlock = false;
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
        afterBlank = false;
      } else if (!lineComplete && _partialListMarker.hasMatch(line)) {
        break;
      } else {
        startBlockAt(pos);
      }
    }

    // indented fence/heading inside a list belongs to the item
    final nested = continuable && indent > 0;

    if (indent <= 3 && !nested && !inHtmlBlock) {
      final math = mathOpener.firstMatch(line);
      if (math != null) {
        // "$$" could still become "$$x$$" on one line
        if (!lineComplete) break;
        if (hasContent) startBlockAt(pos);
        mathEnd = mathBlockCloserFor(math[1]!);
        hasContent = true;
        pos = next;
        continue;
      }

      final opener = _fenceOpener.firstMatch(line);
      if (opener != null) {
        // ```foo``` is inline code, wait for the whole line
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
      // "#" could still become "#tag"
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
        if (end.hasMatch(line.substring(html.end))) {
          htmlChain = true;
        } else {
          htmlEnd = end;
        }
        hasContent = true;
        pos = next;
        continue;
      }

      if (_htmlBlock.hasMatch(line)) inHtmlBlock = true;
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

bool _shallow(String line) => _indentWidth(line) <= 3;
