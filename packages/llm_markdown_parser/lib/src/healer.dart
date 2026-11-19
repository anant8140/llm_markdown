import 'block_splitter.dart';
import 'math.dart';

final RegExp _partialMarkerLine = RegExp(
  r'^[ \t]*(?:`{1,2}|~{1,2}|#{1,6}|[-+*]|\d{1,2}[.)]?|\d{3,9}[.)]|>)[ \t]*$',
);
final RegExp _tableDelimiterRow = RegExp(
  r'^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$',
);
final RegExp _partialTableDelimiter = RegExp(r'^ {0,3}\|[ \t:|-]*$');
final RegExp _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

// "> [!NO": the start of an alert marker such as "> [!NOTE]"
final RegExp _partialAlertMarker = RegExp(
  r'^ {0,3}>[ \t]*\[![A-Za-z]*\]?[ \t]*$',
);

/// Returns [source] changed so that its unfinished end renders cleanly.
///
/// [source] is the end of a Markdown document that is still arriving. The
/// result closes what was left open and hides what cannot be shown yet:
///
/// * an unclosed fenced code block is closed, and a half-typed closing fence
///   or info string is hidden;
/// * unclosed `**bold**`, `*italic*`, `_italic_`, `~~strike~~` and
///   `` `code` `` on the last line are closed;
/// * a link whose address is still arriving shows only its text, and an
///   image whose address is still arriving is hidden;
/// * a table header waiting for its delimiter row, and a table row that is
///   still being typed, are hidden;
/// * a last line that is only the start of a list item, heading, quote or
///   fence is hidden.
///
/// Complete Markdown is returned unchanged. Call this only while the text is
/// still arriving: once it is complete, parse it as it is.
String healIncompleteMarkdown(String source, {bool dollarMath = true}) {
  final mathOpener = mathOpenerFor(dollar: dollarMath);
  if (source.contains('\r')) {
    // a chunk can end between \r and \n
    source = source.replaceAll('\r\n', '\n');
    if (source.endsWith('\r')) source = source.substring(0, source.length - 1);
  }
  if (source.isEmpty) return source;
  final lines = source.split('\n');
  final endsWithNewline = source.endsWith('\n');

  OpenFence? fence;
  var fenceLine = -1;
  RegExp? mathEnd;
  for (var i = 0; i < lines.length; i++) {
    final line = withoutCarriageReturn(lines[i]);
    if (mathEnd != null) {
      if (mathEnd.hasMatch(line)) mathEnd = null;
      continue;
    }
    if (fence == null) {
      final math = mathOpener.firstMatch(line);
      if (math != null) {
        mathEnd = mathBlockCloserFor(math[1]!);
        continue;
      }
      final opened = fenceOpenedBy(line);
      if (opened != null) {
        fence = opened;
        fenceLine = i;
      }
    } else if (fence.isClosedBy(line)) {
      fence = null;
    }
  }
  // an open math block is shown as source, nothing to heal
  if (mathEnd != null) return source;
  if (fence != null) {
    return _closeFence(lines, fence, fenceLine, endsWithNewline);
  }

  var last = lines.length - 1;
  if (endsWithNewline) last--;
  if (last < 0 || isBlank(lines[last])) return source;
  final partial = !endsWithNewline;

  final keep = _linesBeforeIncompleteTable(lines, last, partial);
  if (keep != null) return _joinFirst(lines, keep);

  if (partial &&
      (_partialMarkerLine.hasMatch(lines[last]) ||
          _partialAlertMarker.hasMatch(lines[last]))) {
    return _joinFirst(lines, last);
  }

  final healed = _healHtml(healIncompleteInline(lines[last]));
  if (healed == lines[last]) return source;
  lines[last] = healed;
  return lines.join('\n');
}

String _joinFirst(List<String> lines, int count) =>
    count == 0 ? '' : '${lines.take(count).join('\n')}\n';

String _closeFence(
  List<String> lines,
  OpenFence fence,
  int fenceLine,
  bool endsWithNewline,
) {
  final body = List<String>.of(lines);
  if (!endsWithNewline) {
    final lastIndex = body.length - 1;
    final last = withoutCarriageReturn(body[lastIndex]);
    if (lastIndex == fenceLine) {
      // don't show "pyth" as the language
      body[lastIndex] = '${fence.indent}${fence.marker}';
    } else if (RegExp(
      '^ {0,3}${RegExp.escape(fence.char)}+\$',
    ).hasMatch(last)) {
      // closing fence being typed
      body.removeLast();
    }
  }
  var text = body.join('\n');
  if (!text.endsWith('\n')) text = '$text\n';
  return '$text${fence.indent}${fence.marker}';
}

int? _linesBeforeIncompleteTable(List<String> lines, int last, bool partial) {
  bool isRow(int i) => i >= 0 && lines[i].trimLeft().startsWith('|');

  if (partial &&
      last >= 1 &&
      _partialTableDelimiter.hasMatch(lines[last]) &&
      isRow(last - 1) &&
      !_isTableBody(lines, last - 1)) {
    // delimiter row being typed
    return last - 1;
  }
  if (!isRow(last)) return null;
  if (_isTableBody(lines, last)) return partial ? last : null;
  if (last == 0 || !isRow(last - 1)) {
    // maybe a header, wait for the delimiter row
    return last;
  }
  return null;
}

bool _isTableBody(List<String> lines, int index) {
  for (var i = index - 1; i >= 1; i--) {
    final line = lines[i];
    if (!line.trimLeft().startsWith('|')) return false;
    if (_tableDelimiterRow.hasMatch(line)) return true;
  }
  return false;
}

class _Masked {
  _Masked(this.text, this.openCodeStart, this.openCodeLength);

  final String text;

  final int openCodeStart;

  final int openCodeLength;
}

const int _maskUnit = 0x01;
const int _backtick = 0x60;
const int _backslash = 0x5c;

_Masked _mask(String line) {
  final units = List<int>.of(line.codeUnits);
  var openStart = -1;
  var openLength = 0;
  var i = 0;
  while (i < units.length) {
    final unit = units[i];
    if (unit == _backslash && i + 1 < units.length) {
      units[i] = _maskUnit;
      units[i + 1] = _maskUnit;
      i += 2;
      continue;
    }
    if (unit != _backtick) {
      i++;
      continue;
    }
    var run = 0;
    while (i + run < units.length && units[i + run] == _backtick) {
      run++;
    }
    var closing = -1;
    var j = i + run;
    while (j < units.length) {
      if (units[j] != _backtick) {
        j++;
        continue;
      }
      var other = 0;
      while (j + other < units.length && units[j + other] == _backtick) {
        other++;
      }
      if (other == run) {
        closing = j;
        break;
      }
      j += other;
    }
    final end = closing == -1 ? units.length : closing + run;
    for (var k = i; k < end; k++) {
      units[k] = _maskUnit;
    }
    if (closing == -1) {
      openStart = i;
      openLength = run;
      break;
    }
    i = end;
  }
  return _Masked(String.fromCharCodes(units), openStart, openLength);
}

String healIncompleteInline(String line) => _closeDelimiters(_healLinks(line));

String _healLinks(String line) {
  final masked = _mask(line).text;

  // [text](https://exa -> text
  final destination = masked.lastIndexOf('](');
  if (destination != -1 && !masked.contains(')', destination)) {
    final start = _matchingOpenBracket(masked, destination);
    if (start != -1) {
      if (start > 0 && masked[start - 1] == '!') {
        return line.substring(0, start - 1);
      }
      return line.substring(0, start) + line.substring(start + 1, destination);
    }
  }

  // [text -> text, ![alt -> nothing
  final open = <int>[];
  for (var i = 0; i < masked.length; i++) {
    final char = masked[i];
    if (char == '[') {
      open.add(i);
    } else if (char == ']' && open.isNotEmpty) {
      open.removeLast();
    }
  }
  var result = line;
  for (final position in open.reversed) {
    if (position > 0 && masked[position - 1] == '!') {
      result = result.substring(0, position - 1);
    } else if (position > result.length) {
      continue;
    } else if (masked.startsWith('^', position + 1) ||
        (position > 0 && masked[position - 1] == ']')) {
      // "[^1" is a footnote mark and "[text][re" the name of a reference:
      // neither is text to show
      result = result.substring(0, position);
    } else if (position < result.length) {
      result = result.substring(0, position) + result.substring(position + 1);
    }
  }
  return result;
}

int _matchingOpenBracket(String masked, int closing) {
  var depth = 0;
  for (var i = closing - 1; i >= 0; i--) {
    final char = masked[i];
    if (char == ']') {
      depth++;
    } else if (char == '[') {
      if (depth == 0) return i;
      depth--;
    }
  }
  return -1;
}

class _Delimiter {
  const _Delimiter(this.char, this.size);

  final String char;
  final int size;
}

bool _isSpace(String char) => char == ' ' || char == '\t';

String _closeDelimiters(String line) {
  final masked = _mask(line);
  final text = masked.text;
  final stack = <_Delimiter>[];
  int? dangling;

  var i = 0;
  while (i < text.length) {
    final char = text[i];
    if (char != '*' && char != '_' && char != '~' && char != '=') {
      i++;
      continue;
    }
    var end = i;
    while (end < text.length && text[end] == char) {
      end++;
    }
    var count = end - i;
    final before = i > 0 ? text[i - 1] : null;
    final after = end < text.length ? text[end] : null;
    if ((char == '~' || char == '=') && count != 2) {
      i = end;
      continue;
    }
    var canOpen = after != null && !_isSpace(after);
    var canClose = before != null && !_isSpace(before);
    // 2*3 is usually math, not emphasis
    if (char == '*' &&
        before != null &&
        after != null &&
        _wordCharacter.hasMatch(before) &&
        _wordCharacter.hasMatch(after)) {
      canOpen = false;
    }
    // snake_case and a==b are not emphasis or a highlight
    if (char == '_' || char == '=') {
      if (before != null && _wordCharacter.hasMatch(before)) canOpen = false;
      if (after != null && _wordCharacter.hasMatch(after)) canClose = false;
    }

    if (after == null) {
      // trailing run: keep it only if it closes something
      var remaining = count;
      var depth = stack.length;
      while (canClose &&
          remaining > 0 &&
          depth > 0 &&
          stack[depth - 1].char == char &&
          stack[depth - 1].size <= remaining) {
        remaining -= stack[depth - 1].size;
        depth--;
      }
      if (canClose && remaining == 0) {
        stack.removeRange(depth, stack.length);
      } else {
        dangling = i;
      }
      break;
    }

    if (canClose) {
      while (count > 0 &&
          stack.isNotEmpty &&
          stack.last.char == char &&
          stack.last.size <= count) {
        count -= stack.removeLast().size;
      }
    }
    if (count > 0 && canOpen) {
      if (char == '~' || char == '=') {
        stack.add(_Delimiter(char, 2));
      } else {
        if (count >= 2) {
          stack.add(_Delimiter(char, 2));
          count -= 2;
        }
        if (count >= 1) stack.add(_Delimiter(char, 1));
      }
    }
    i = end;
  }

  var result = dangling == null ? line : line.substring(0, dangling);
  if (masked.openCodeStart != -1) {
    if (masked.openCodeStart + masked.openCodeLength == line.length) {
      result = line.substring(0, masked.openCodeStart);
    } else {
      result = '$result${'`' * masked.openCodeLength}';
    }
  }
  if (stack.isEmpty) return result;

  final closers = stack.reversed.map((d) => d.char * d.size).join();
  final trimmed = result.trimRight();
  return '$trimmed$closers${result.substring(trimmed.length)}';
}

final RegExp _partialTag = RegExp(r'<(?:/?[A-Za-z][A-Za-z0-9]*[^<>]*)?$');
final RegExp _openSafeTag = RegExp(
  r'<(sub|sup|kbd|mark|u|ins|small)>(?![^<]*</\1>)[^<]*$',
  caseSensitive: false,
);

// "text <su" hides the half tag; "<sub>2" closes it as "<sub>2</sub>".
String _healHtml(String line) {
  // first drop a tag that is still being typed, also a closing one, so
  // "<sub>2</su" becomes "<sub>2" and is then closed like any open tag
  final whole = line.replaceFirst(_partialTag, '');
  final open = _openSafeTag.firstMatch(whole);
  if (open != null) return '$whole</${open[1]}>';
  return whole;
}
