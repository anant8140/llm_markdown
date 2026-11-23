import 'dart:async';

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
/// place as more arrives; copy them to keep a snapshot.
///
/// With [lenient], the default, text before the first `{` or `[` and after
/// the document ends is skipped, so a reply like ```` ```json {...} ``` ````
/// or "Here it is: {...}" parses, and a trailing comma is allowed. JSON
/// that is wrong, not just unfinished, throws a [FormatException].
class PartialJsonParser {
  /// A parser; see [lenient].
  PartialJsonParser({this.lenient = true});

  /// Whether text around the document and trailing commas are allowed.
  final bool lenient;

  final _stack = <_Frame>[];
  Object? _root;
  var _started = false;
  var _done = false;
  var _offset = 0;

  // the scalar being read, if any
  _Scalar? _scalar;

  /// Whether the document is complete.
  bool get isComplete => _done;

  /// Whether the document has started, so [value] means something.
  bool get hasValue => _started && (_stack.isNotEmpty || _done || _shows);

  bool get _shows => _scalar?.shown != null;

  /// The value so far: a map, list, string, number, bool or null.
  Object? get value {
    final scalar = _scalar;
    if (scalar != null) {
      final shown = scalar.shown;
      if (shown != null) _place(shown.value);
    }
    return _root;
  }

  /// The path to the value still being written, such as
  /// `['items', 2, 'title']`; empty when the document is complete or the
  /// root itself is being written.
  ///
  /// A value whose path is not the start of this one is finished and will
  /// not change.
  List<Object> get pendingPath {
    final path = <Object>[];
    if (_done) return path;
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

  /// Adds the next piece of the document.
  void add(String chunk) {
    for (var i = 0; i < chunk.length; i++, _offset++) {
      _char(chunk.codeUnitAt(i));
    }
  }

  /// Ends the document, as at the end of a stream; throws a
  /// [FormatException] if it is not complete. A number at the very end
  /// completes here.
  Object? close() {
    final scalar = _scalar;
    if (scalar is _NumberScalar && _stack.isEmpty) _finishScalar(scalar);
    if (!_done) {
      throw FormatException('The JSON ended in the middle', null, _offset);
    }
    return _root;
  }

  Never _fail(String message) => throw FormatException(message, null, _offset);

  void _char(int c) {
    final scalar = _scalar;
    if (scalar != null) {
      if (scalar.add(c, this)) return;
      // the number ended at this character, which is read again below
      _finishScalar(scalar);
    }
    if (_done) {
      if (!lenient && !_isSpace(c)) _fail('Text after the JSON');
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

  void _objectChar(_ObjectFrame frame, int c) {
    switch (frame.state) {
      case _Obj.keyOrEnd || _Obj.key:
        if (c == _quote) {
          frame.valueStarted = false;
          _scalar = _StringScalar(isKey: true);
        } else if (c == _closeBrace &&
            (frame.state == _Obj.keyOrEnd || lenient)) {
          _endContainer();
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
        _stack.add(_ObjectFrame(map));
      case _openBracket:
        final list = <Object?>[];
        _place(list);
        _stack.add(_ArrayFrame(list));
      case _quote:
        _scalar = _StringScalar(isKey: false);
      case 0x74: // t
        _scalar = _LiteralScalar('true', true);
      case 0x66: // f
        _scalar = _LiteralScalar('false', false);
      case 0x6E: // n
        _scalar = _LiteralScalar('null', null);
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
    if (scalar is _StringScalar && scalar.isKey) {
      final frame = _stack.last as _ObjectFrame;
      frame.key = result as String;
      frame.state = _Obj.colon;
      return;
    }
    _place(result);
    _valueEnded();
  }

  void _endContainer() {
    _stack.removeLast();
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
}

const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _quote = 0x22;
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
  // Takes [c]; false when [c] is not part of the scalar (a number's end).
  bool add(int c, PartialJsonParser parser);
  _Shown? get shown;
  Object? result(PartialJsonParser parser);
}

class _StringScalar extends _Scalar {
  _StringScalar({required this.isKey});
  final bool isKey;
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
    } else if (c == 0x22) {
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
  _Shown? get shown {
    if (isKey) return null;
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

final _fullNumber = RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$');
final _numberStart = RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?');

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

  static num _parse(String text) => text.contains(RegExp('[.eE]'))
      ? double.parse(text)
      : int.tryParse(text) ?? double.parse(text);

  @override
  _Shown? get shown {
    final match = _numberStart.firstMatch(_text.toString());
    if (match == null) return null;
    return _Shown(_parse(match[0]!));
  }

  @override
  Object? result(PartialJsonParser parser) {
    final text = _text.toString();
    if (!_fullNumber.hasMatch(text)) parser._fail('Bad number "$text"');
    return _parse(text);
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
  _Shown? get shown => _Shown(meaning);

  @override
  Object? result(PartialJsonParser parser) => meaning;
}

/// Parses [text], a JSON document that may be cut off, and gives the value
/// so far; see [PartialJsonParser]. Returns null when the document has not
/// started.
Object? parsePartialJson(String text, {bool lenient = true}) =>
    (PartialJsonParser(lenient: lenient)..add(text)).value;

/// Turns a stream of JSON text pieces into the value so far after each
/// piece, as [PartialJsonParser] reads it. Pieces that don't change what
/// has started are skipped; the stream ends with an error if the JSON is
/// wrong or ends in the middle.
class PartialJsonDecoder extends StreamTransformerBase<String, Object?> {
  /// A decoder; see [PartialJsonParser.lenient].
  const PartialJsonDecoder({this.lenient = true});

  /// Whether text around the document and trailing commas are allowed.
  final bool lenient;

  @override
  Stream<Object?> bind(Stream<String> stream) async* {
    final parser = PartialJsonParser(lenient: lenient);
    await for (final chunk in stream) {
      parser.add(chunk);
      if (parser.hasValue) yield parser.value;
    }
    final done = parser.isComplete;
    final value = parser.close();
    if (!done) yield value;
  }
}
