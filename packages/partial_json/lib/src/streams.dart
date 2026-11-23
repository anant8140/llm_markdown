import 'dart:async';

import 'parser.dart';

/// Turns a stream of JSON text pieces into the value so far after each
/// piece, as [PartialJsonParser] reads it. Pieces before the document
/// starts give nothing; the stream ends with an error if the JSON is wrong
/// or ends in the middle.
class PartialJsonDecoder extends StreamTransformerBase<String, Object?> {
  /// A decoder; see [PartialJsonParser] for [lenient] and [repair].
  const PartialJsonDecoder({
    this.lenient = true,
    this.repair = false,
    this.snapshots = false,
  });

  /// Whether text around the document and trailing commas are allowed.
  final bool lenient;

  /// Whether common mistakes in model JSON are read anyway.
  final bool repair;

  /// Whether each value given is a copy that later pieces don't change;
  /// otherwise it is the parser's own, updated in place.
  final bool snapshots;

  @override
  Stream<Object?> bind(Stream<String> stream) async* {
    final parser = PartialJsonParser(lenient: lenient, repair: repair);
    await for (final chunk in stream) {
      parser.add(chunk);
      if (parser.hasValue) yield snapshots ? parser.snapshot() : parser.value;
    }
    final done = parser.isComplete;
    parser.close();
    if (!done) yield snapshots ? parser.snapshot() : parser.value;
  }
}

/// Gives each item of the list at [path] as soon as that item is finished,
/// converted with [convert]: a list of recipes from a model becomes a
/// `Stream<Recipe>` that shows each recipe while the next is written.
///
/// ```dart
/// textStream.transform(
///   PartialJsonItemDecoder(path: ['recipes'], convert: (json) => Recipe.fromJson(json as Map<String, dynamic>)),
/// );
/// ```
///
/// An empty [path] means the document itself is the list.
class PartialJsonItemDecoder<T> extends StreamTransformerBase<String, T> {
  /// A decoder of the items at [path].
  const PartialJsonItemDecoder({
    required this.path,
    required this.convert,
    this.lenient = true,
    this.repair = false,
  });

  /// The path of the list, such as `['data', 'items']`.
  final List<Object> path;

  /// Makes an item from its JSON value.
  final T Function(Object? json) convert;

  /// Whether text around the document and trailing commas are allowed.
  final bool lenient;

  /// Whether common mistakes in model JSON are read anyway.
  final bool repair;

  @override
  Stream<T> bind(Stream<String> stream) async* {
    final items = <Object?>[];
    final parser = PartialJsonParser(
      lenient: lenient,
      repair: repair,
      onComplete: (at, value) {
        if (at.length == path.length + 1 && at.last is int && _starts(at)) {
          items.add(value);
        }
      },
    );
    await for (final chunk in stream) {
      parser.add(chunk);
      for (final item in items) {
        yield convert(item);
      }
      items.clear();
    }
    parser.close();
    for (final item in items) {
      yield convert(item);
    }
  }

  bool _starts(List<Object> at) {
    for (var i = 0; i < path.length; i++) {
      if (at[i] != path[i]) return false;
    }
    return true;
  }
}

/// One document of a stream of several, as [PartialJsonDocumentsDecoder]
/// gives it.
class PartialJsonDocument {
  /// The document number [index] with [value].
  const PartialJsonDocument(this.index, this.value, {required this.isComplete});

  /// Which document this is, from 0.
  final int index;

  /// Its value so far.
  final Object? value;

  /// Whether it is finished; a finished document is given once more after
  /// its last partial value.
  final bool isComplete;

  @override
  String toString() =>
      'PartialJsonDocument($index, $value${isComplete ? '' : ', partial'})';
}

/// Reads a stream of several JSON documents one after another, such as
/// JSON Lines (NDJSON) or the objects a model writes one by one, and gives
/// each document's value as it grows and once more when it is finished.
class PartialJsonDocumentsDecoder
    extends StreamTransformerBase<String, PartialJsonDocument> {
  /// A decoder; with [lenient], text between the documents is skipped.
  const PartialJsonDocumentsDecoder({this.lenient = true, this.repair = false});

  /// Whether text between documents and trailing commas are allowed.
  final bool lenient;

  /// Whether common mistakes in model JSON are read anyway.
  final bool repair;

  @override
  Stream<PartialJsonDocument> bind(Stream<String> stream) async* {
    var index = 0;
    var parser = PartialJsonParser(lenient: lenient, repair: repair);
    await for (final chunk in stream) {
      var start = 0;
      while (start < chunk.length) {
        start = feedUntilDone(parser, chunk, start);
        if (parser.isComplete) {
          yield PartialJsonDocument(index++, parser.value, isComplete: true);
          parser = PartialJsonParser(lenient: lenient, repair: repair);
        }
      }
      if (parser.hasValue) {
        yield PartialJsonDocument(index, parser.snapshot(), isComplete: false);
      }
    }
    if (parser.hasValue) {
      final done = parser.isComplete;
      final value = parser.close();
      if (!done) yield PartialJsonDocument(index, value, isComplete: true);
    }
  }
}

/// Collects the arguments of streamed tool calls, which arrive as JSON
/// pieces per call: OpenAI's `function.arguments` deltas or Anthropic's
/// `input_json_delta`. Each call's arguments can be shown while written.
///
/// ```dart
/// final args = ToolArgumentsParser();
/// args.add('call_1', '{"city": "Par');
/// args['call_1']; // {city: Par}
/// ```
class ToolArgumentsParser {
  /// A parser; see [PartialJsonParser.repair].
  ToolArgumentsParser({this.repair = false});

  /// Whether common mistakes in model JSON are read anyway.
  final bool repair;

  final _calls = <String, PartialJsonParser>{};

  /// Adds the next piece of the arguments of call [id] and gives them so
  /// far.
  Object? add(String id, String piece) {
    final parser = _calls.putIfAbsent(
      id,
      () => PartialJsonParser(lenient: false, repair: repair),
    );
    parser.add(piece);
    return parser.value;
  }

  /// The arguments of call [id] so far, or null.
  Object? operator [](String id) => _calls[id]?.value;

  /// Whether the arguments of call [id] are complete JSON.
  bool isComplete(String id) => _calls[id]?.isComplete ?? false;

  /// The calls seen, in order.
  Iterable<String> get ids => _calls.keys;

  /// Ends call [id] and gives its arguments; throws a [FormatException]
  /// when they are not complete. A call with no pieces has no arguments:
  /// an empty map.
  Object? close(String id) {
    final parser = _calls[id];
    if (parser == null || !parser.hasValue) return <String, Object?>{};
    return parser.close();
  }

  /// Forgets call [id].
  void remove(String id) => _calls.remove(id);
}
