/// Parses a JSON document that arrives in pieces, giving at every point the
/// value so far.
///
/// ```dart
/// final parser = PartialJsonParser();
/// parser.add('{"title": "Stre');
/// parser.value; // {title: Stre}
/// parser.add('aming", "tags": ["a", "b');
/// parser.value; // {title: Streaming, tags: [a, b]}
/// ```
///
/// Strings show the text so far, numbers the digits so far, and `t`, `f`
/// and `n` already show `true`, `false` and `null`. A key shows once its
/// value has started. Each chunk is read once, so a long document costs no
/// more than parsing it whole.
///
/// The maps and lists of [value] are the parser's own and are updated in
/// place as more arrives; [snapshot] gives a copy.
///
/// With [lenient], the default, text before the first `{` or `[` and after
/// the document ends is skipped, so a reply like ```` ```json {...} ``` ````
/// or "Here it is: {...}" parses, and a trailing comma is allowed. JSON
/// that is wrong, not just unfinished, throws a [FormatException] that
/// names the line and column.
class PartialJsonParser {
  /// A parser; see the fields for what each setting does.
  PartialJsonParser({
    this.lenient = true,
    this.repair = false,
    this.partialStrings = true,
    this.partialNumbers = true,
    this.bigInts = false,
    this.onComplete,
  });

  /// Whether text around the document and trailing commas are allowed.
  final bool lenient;

  /// Whether the mistakes models make in JSON are read anyway: strings in
  /// single quotes, keys without quotes, `//` and `/* */` comments, and
  /// Python's `True`, `False` and `None`. Off by default, since it accepts
  /// text that isn't JSON.
  final bool repair;

  /// Whether a string still being written shows its text so far; when
  /// false it shows only once it is finished.
  final bool partialStrings;

  /// Whether a number still being written shows its digits so far, and a
  /// started `true`, `false` or `null` shows already; when false they show
  /// only once finished.
  final bool partialNumbers;

  /// Whether a whole number too large for an `int` (or, on the web, too
  /// large to be exact) is a [BigInt] instead of a less exact [double].
  final bool bigInts;

  /// Called whenever a value is finished, with its path and the value: a
  /// string, number, bool or null, and a map or list once it is closed.
  /// The document itself comes last, with an empty path.
  final void Function(List<Object> path, Object? value)? onComplete;

  final _stack = <_Frame>[];
  Object? _root;
  var _started = false;
  var _done = false;
  var _offset = 0;
  var _line = 1;
  var _column = 1;

  // the scalar being read, if any
  _Scalar? _scalar;

  // a comment being skipped (repair): 1 after "/", 2 in a // comment,
  // 3 in a /* */ comment, 4 after its "*"
  var _comment = 0;

  final _changed = <String, List<Object>>{};

  /// Whether the document is complete.
  bool get isComplete => _done;

  /// Whether the document has started, so [value] means something.
  bool get hasValue => _started && (_stack.isNotEmpty || _done || _shows);

  bool get _shows => _scalar?.shown(this) != null;

  /// The value so far: a map, list, string, number, bool or null.
  Object? get value {
    final scalar = _scalar;
    if (scalar != null) {
      final shown = scalar.shown(this);
      if (shown != null) _place(shown.value);
    }
    return _root;
  }

  /// A copy of [value] that later pieces don't change, for state that is
  /// compared by identity (Riverpod, Bloc, `setState` with old values).
  Object? snapshot() => _copy(value);

  static Object? _copy(Object? value) => switch (value) {
    Map() => {for (final e in value.entries) e.key: _copy(e.value)},
    List() => [for (final e in value) _copy(e)],
    _ => value,
  };

  /// The path to the value still being written, such as
  /// `['items', 2, 'title']`; empty when the document is complete or the
  /// root itself is being written.
  ///
  /// A value whose path is not the start of this one is finished and will
  /// not change.
  List<Object> get pendingPath => _done ? <Object>[] : _path();

  /// The paths of the values that the last [add] started, changed or
  /// finished, each once, outermost first where they nest.
  List<List<Object>> get changedPaths => _changed.values.toList();

  List<Object> _path() {
    final path = <Object>[];
    for (final frame in _stack) {
      switch (frame) {
        case _ObjectFrame(:final key?) when frame.valueStarted:
          path.add(key);
        case _ArrayFrame() when frame.valueStarted:
          path.add(frame.slotAdded ? frame.list.length - 1 : frame.list.length);
        default:
          return path;
      }
    }
    return path;
  }

  void _change() {
    final path = _path();
    _changed[path.join('\u0000')] = path;
  }

  /// Adds the next piece of the document.
  void add(String chunk) {
    _changed.clear();
    _feed(chunk, 0, untilDone: false);
    final scalar = _scalar;
    if (scalar != null && scalar.shown(this) != null) _change();
  }

  // Reads [chunk] from [start]; with [untilDone] it stops after the
  // character that completes the document and gives the index after it.
  int _feed(String chunk, int start, {required bool untilDone}) {
    for (var i = start; i < chunk.length; i++) {
      final c = chunk.codeUnitAt(i);
      _char(c);
      _offset++;
      if (c == 0x0A) {
        _line++;
        _column = 1;
      } else {
        _column++;
      }
      if (untilDone && _done) return i + 1;
    }
    return chunk.length;
  }

  /// Ends the document, as at the end of a stream; throws a
  /// [FormatException] if it is not complete. A number at the very end
  /// completes here.
  Object? close() {
    final scalar = _scalar;
    if (scalar is _NumberScalar && _stack.isEmpty) _finishScalar(scalar);
    if (!_done) _fail('The JSON ended in the middle');
    return _root;
  }

  Never _fail(String message) => throw FormatException(
    '$message at line $_line, column $_column',
    null,
    _offset,
  );

  void _char(int c) {
    if (_comment != 0) {
      _commentChar(c);
      return;
    }
    final scalar = _scalar;
    if (scalar != null) {
      if (scalar.add(c, this)) return;
      // the number or bare key ended at this character, read again below
      _finishScalar(scalar);
    }
    if (_done) {
      if (!lenient && !_isSpace(c)) _fail('Text after the JSON');
      return;
    }
    if (repair && c == 0x2F && (_stack.isNotEmpty || !lenient)) {
      _comment = 1;
      return;
    }
    if (_stack.isEmpty) {
      if (_isSpace(c)) return;
      if (lenient && c != _openBrace && c != _openBracket) return;
      _startValue(c);
      return;
    }
    final frame = _stack.last;
    if (_isSpace(c)) return;
    switch (frame) {
      case _ObjectFrame():
        _objectChar(frame, c);
      case _ArrayFrame():
        _arrayChar(frame, c);
    }
  }

  void _commentChar(int c) {
    switch (_comment) {
      case 1:
        if (c == 0x2F) {
          _comment = 2;
        } else if (c == 0x2A) {
          _comment = 3;
        } else {
          _fail('Unexpected "/"');
        }
      case 2:
        if (c == 0x0A || c == 0x0D) _comment = 0;
      case 3:
        if (c == 0x2A) _comment = 4;
      case 4:
        if (c == 0x2F) {
          _comment = 0;
        } else if (c != 0x2A) {
          _comment = 3;
        }
    }
  }

  void _objectChar(_ObjectFrame frame, int c) {
    switch (frame.state) {
      case _Obj.keyOrEnd || _Obj.key:
        if (c == _quote || (repair && c == _apostrophe)) {
          frame.valueStarted = false;
          _scalar = _StringScalar(isKey: true, quote: c);
        } else if (c == _closeBrace &&
            (frame.state == _Obj.keyOrEnd || lenient)) {
          _endContainer();
        } else if (repair && _isIdentStart(c)) {
          frame.valueStarted = false;
          _scalar = _BareKeyScalar()..add(c, this);
        } else {
          _fail('Expected a key');
        }
      case _Obj.colon:
        if (c != _colon) _fail('Expected ":"');
        frame.state = _Obj.value;
      case _Obj.value:
        frame.valueStarted = true;
        _startValue(c);
      case _Obj.commaOrEnd:
        if (c == _comma) {
          frame.state = _Obj.key;
          frame.key = null;
          frame.valueStarted = false;
        } else if (c == _closeBrace) {
          _endContainer();
        } else {
          _fail('Expected "," or "}"');
        }
    }
  }

  void _arrayChar(_ArrayFrame frame, int c) {
    switch (frame.state) {
      case _Arr.valueOrEnd || _Arr.value:
        if (c == _closeBracket && (frame.state == _Arr.valueOrEnd || lenient)) {
          _endContainer();
          return;
        }
        frame.valueStarted = true;
        frame.slotAdded = false;
        frame.state = _Arr.commaOrEnd;
        _startValue(c);
      case _Arr.commaOrEnd:
        if (c == _comma) {
          frame.state = _Arr.value;
          frame.valueStarted = false;
        } else if (c == _closeBracket) {
          _endContainer();
        } else {
          _fail('Expected "," or "]"');
        }
    }
  }

  void _startValue(int c) {
    _started = true;
    if (_stack case [..., _ObjectFrame frame]) frame.state = _Obj.commaOrEnd;
    switch (c) {
      case _openBrace:
        final map = <String, Object?>{};
        _place(map);
        _change();
        _stack.add(_ObjectFrame(map));
      case _openBracket:
        final list = <Object?>[];
        _place(list);
        _change();
        _stack.add(_ArrayFrame(list));
      case _quote:
        _scalar = _StringScalar(isKey: false, quote: c);
      case _apostrophe when repair:
        _scalar = _StringScalar(isKey: false, quote: c);
      case 0x74: // t
        _scalar = _LiteralScalar('true', true);
      case 0x66: // f
        _scalar = _LiteralScalar('false', false);
      case 0x6E: // n
        _scalar = _LiteralScalar('null', null);
      case 0x54 when repair: // T
        _scalar = _LiteralScalar('True', true);
      case 0x46 when repair: // F
        _scalar = _LiteralScalar('False', false);
      case 0x4E when repair: // N
        _scalar = _LiteralScalar('None', null);
      default:
        if (c == 0x2D || (c >= 0x30 && c <= 0x39)) {
          _scalar = _NumberScalar()..add(c, this);
        } else {
          _fail('Unexpected character "${String.fromCharCode(c)}"');
        }
    }
  }

  // Puts [value] where the value being written goes.
  void _place(Object? value) {
    if (_stack.isEmpty) {
      _root = value;
      return;
    }
    switch (_stack.last) {
      case _ObjectFrame(:final map, :final key?):
        map[key] = value;
      case _ArrayFrame frame:
        if (frame.slotAdded) {
          frame.list[frame.list.length - 1] = value;
        } else {
          frame.list.add(value);
          frame.slotAdded = true;
        }
      default:
    }
  }

  void _finishScalar(_Scalar scalar) {
    _scalar = null;
    final result = scalar.result(this);
    if (scalar.isKey) {
      final frame = _stack.last as _ObjectFrame;
      frame.key = result as String;
      frame.state = _Obj.colon;
      return;
    }
    _place(result);
    _change();
    onComplete?.call(_path(), result);
    _valueEnded();
  }

  void _endContainer() {
    final frame = _stack.removeLast();
    onComplete?.call(_path(), switch (frame) {
      _ObjectFrame(:final map) => map,
      _ArrayFrame(:final list) => list,
    });
    _valueEnded();
  }

  // The value being written is finished.
  void _valueEnded() {
    if (_stack.isEmpty) {
      _done = true;
    } else {
      _stack.last.valueStarted = false;
    }
  }

  // called by scalars when they end on their own closing character
  void _scalarEnded(_Scalar scalar) => _finishScalar(scalar);

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;

  static bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;
}

const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _quote = 0x22;
const _apostrophe = 0x27;
const _colon = 0x3A;
const _comma = 0x2C;

sealed class _Frame {
  // whether a value in it is being written
  var valueStarted = false;
}

enum _Obj { keyOrEnd, key, colon, value, commaOrEnd }

enum _Arr { valueOrEnd, value, commaOrEnd }

class _ObjectFrame extends _Frame {
  _ObjectFrame(this.map);
  final Map<String, Object?> map;
  var state = _Obj.keyOrEnd;
  String? key;
}

class _ArrayFrame extends _Frame {
  _ArrayFrame(this.list);
  final List<Object?> list;
  var state = _Arr.valueOrEnd;
  // whether the value being written has its place in the list yet
  var slotAdded = false;
}

// What a scalar shows so far; null when nothing yet (a lone "-").
class _Shown {
  const _Shown(this.value);
  final Object? value;
}

sealed class _Scalar {
  bool get isKey => false;
  // Takes [c]; false when [c] is not part of the scalar (its end).
  bool add(int c, PartialJsonParser parser);
  _Shown? shown(PartialJsonParser parser);
  Object? result(PartialJsonParser parser);
}

class _StringScalar extends _Scalar {
  _StringScalar({required this.isKey, required this.quote});
  @override
  final bool isKey;
  final int quote;
  final _text = StringBuffer();
  // an escape being read: "\" alone, or "\u" and up to 4 hex digits
  String? _escape;

  @override
  bool add(int c, PartialJsonParser parser) {
    final escape = _escape;
    if (escape != null) {
      if (escape.length == 1) {
        switch (c) {
          case 0x22 || 0x5C || 0x2F:
            _text.writeCharCode(c);
          case 0x27 when parser.repair:
            _text.writeCharCode(c);
          case 0x62:
            _text.writeCharCode(0x08);
          case 0x66:
            _text.writeCharCode(0x0C);
          case 0x6E:
            _text.writeCharCode(0x0A);
          case 0x72:
            _text.writeCharCode(0x0D);
          case 0x74:
            _text.writeCharCode(0x09);
          case 0x75:
            _escape = r'\u';
            return true;
          default:
            parser._fail('Bad escape');
        }
        _escape = null;
        return true;
      }
      if (!_isHex(c)) parser._fail('Bad \\u escape');
      final hex = escape + String.fromCharCode(c);
      if (hex.length == 6) {
        _text.writeCharCode(int.parse(hex.substring(2), radix: 16));
        _escape = null;
      } else {
        _escape = hex;
      }
      return true;
    }
    if (c == 0x5C) {
      _escape = r'\';
    } else if (c == quote) {
      parser._scalarEnded(this);
    } else if (c < 0x20) {
      parser._fail('A control character in a string');
    } else {
      _text.writeCharCode(c);
    }
    return true;
  }

  static bool _isHex(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x46) ||
      (c >= 0x61 && c <= 0x66);

  @override
  _Shown? shown(PartialJsonParser parser) {
    if (isKey || !parser.partialStrings) return null;
    var text = _text.toString();
    // half of a surrogate pair waits for the other half
    if (text.isNotEmpty) {
      final last = text.codeUnitAt(text.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        text = text.substring(0, text.length - 1);
      }
    }
    return _Shown(text);
  }

  @override
  Object? result(PartialJsonParser parser) => _text.toString();
}

// A key without quotes (repair).
class _BareKeyScalar extends _Scalar {
  final _text = StringBuffer();

  @override
  bool get isKey => true;

  @override
  bool add(int c, PartialJsonParser parser) {
    final part = PartialJsonParser._isIdentStart(c) || (c >= 0x30 && c <= 0x39);
    if (!part) return false;
    _text.writeCharCode(c);
    return true;
  }

  @override
  _Shown? shown(PartialJsonParser parser) => null;

  @override
  Object? result(PartialJsonParser parser) => _text.toString();
}

final _fullNumber = RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$');
final _numberStart = RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?');
final _fraction = RegExp('[.eE]');

class _NumberScalar extends _Scalar {
  final _text = StringBuffer();

  @override
  bool add(int c, PartialJsonParser parser) {
    final isPart =
        (c >= 0x30 && c <= 0x39) ||
        c == 0x2D ||
        c == 0x2B ||
        c == 0x2E ||
        c == 0x65 ||
        c == 0x45;
    if (!isPart) return false;
    _text.writeCharCode(c);
    return true;
  }

  static Object _parse(String text, bool bigInts) {
    if (text.contains(_fraction)) return double.parse(text);
    final value = int.tryParse(text);
    if (bigInts) {
      final digits = text.startsWith('-') ? text.substring(1) : text;
      // exact as an int (on the web, ints are doubles)
      if (value != null && (digits.length < 16 || value.toString() == text)) {
        return value;
      }
      return BigInt.parse(text);
    }
    return value ?? double.parse(text);
  }

  @override
  _Shown? shown(PartialJsonParser parser) {
    if (!parser.partialNumbers) return null;
    final match = _numberStart.firstMatch(_text.toString());
    if (match == null) return null;
    return _Shown(_parse(match[0]!, parser.bigInts));
  }

  @override
  Object? result(PartialJsonParser parser) {
    final text = _text.toString();
    if (!_fullNumber.hasMatch(text)) parser._fail('Bad number "$text"');
    return _parse(text, parser.bigInts);
  }
}

class _LiteralScalar extends _Scalar {
  _LiteralScalar(this.word, this.meaning);
  final String word;
  final Object? meaning;
  var _length = 1;

  @override
  bool add(int c, PartialJsonParser parser) {
    if (c != word.codeUnitAt(_length)) parser._fail('Expected "$word"');
    _length++;
    if (_length == word.length) parser._scalarEnded(this);
    return true;
  }

  @override
  _Shown? shown(PartialJsonParser parser) =>
      parser.partialNumbers ? _Shown(meaning) : null;

  @override
  Object? result(PartialJsonParser parser) => meaning;
}

/// Parses [text], a JSON document that may be cut off, and gives the value
/// so far; see [PartialJsonParser] for the settings. Returns null when the
/// document has not started.
Object? parsePartialJson(
  String text, {
  bool lenient = true,
  bool repair = false,
  bool bigInts = false,
}) => (PartialJsonParser(
  lenient: lenient,
  repair: repair,
  bigInts: bigInts,
)..add(text)).value;

/// Reads [text] with [repair] on (single quotes, bare keys, comments,
/// `True`/`False`/`None`, text around it, trailing commas) and gives it as
/// valid JSON; a cut-off document is closed. Throws a [FormatException]
/// when even that can't read it, or when there is no JSON in it.
String repairJson(String text) {
  final parser = PartialJsonParser(repair: true)..add(text);
  if (!parser.hasValue) {
    throw const FormatException('No JSON object or array found');
  }
  return _encode(parser.value);
}

String _encode(Object? value) => switch (value) {
  Map() =>
    '{${[for (final e in value.entries) '${_string(e.key as String)}:${_encode(e.value)}'].join(',')}}',
  List() => '[${value.map(_encode).join(',')}]',
  String() => _string(value),
  double(isFinite: false) => 'null',
  _ => '$value',
};

String _string(String text) {
  final out = StringBuffer('"');
  for (final unit in text.codeUnits) {
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (unit < 0x20) {
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
  return out.toString();
}

/// Internal: reads [chunk] from [start] until a document completes.
int feedUntilDone(PartialJsonParser parser, String chunk, int start) =>
    parser._feed(chunk, start, untilDone: true);
