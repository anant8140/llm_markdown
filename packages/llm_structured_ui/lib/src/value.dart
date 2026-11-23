/// A read helper for a JSON value that may still be arriving.
///
/// Reading never throws: a missing key, an index past the end or a value of
/// another type gives a value whose [exists] is false, `null` from the `as`
/// getters, and empty collections from [asList] and [asMap]. So
/// `data['title'].asString ?? ''` is safe before the title has arrived.
///
/// A value reads the document as it is when the value is made, and the
/// document changes as more arrives. Use a value during the build it was
/// handed to, and take a new one (from `StructuredBuilder` or
/// `StructuredStreamController.data`) after each change.
class StructuredValue {
  /// A value for JSON that is already whole, such as a decoded reply from
  /// the history. Everything in it [isDone].
  const StructuredValue(Object? json)
    : raw = json,
      exists = true,
      path = const [],
      _pendingPath = const [],
      _complete = true,
      _live = false,
      _parentPending = false;

  /// A value that is not there and is not going to arrive.
  const StructuredValue.missing()
    : raw = null,
      exists = false,
      path = const [],
      _pendingPath = const [],
      _complete = true,
      _live = false,
      _parentPending = false;

  /// The root of a document that is being read. [pendingPath] is the path
  /// of the value still being written, [isComplete] whether the document
  /// is whole, and [isLive] whether more can still arrive (false after an
  /// error or once the stream ended).
  const StructuredValue.root(
    Object? json, {
    required this.exists,
    required List<Object> pendingPath,
    required bool isComplete,
    required bool isLive,
  }) : raw = json,
       path = const [],
       _pendingPath = pendingPath,
       _complete = isComplete,
       _live = isLive,
       _parentPending = false;

  const StructuredValue._(
    this.raw,
    this.exists,
    this.path,
    this._pendingPath,
    this._complete,
    this._live,
    this._parentPending,
  );

  /// The JSON value itself: a map, list, string, number, bool or null.
  /// Null when the value is missing; see [exists].
  final Object? raw;

  /// Whether the value has started to arrive. A JSON `null` exists.
  final bool exists;

  /// Where the value is in the document, such as `['steps', 2, 'text']`.
  final List<Object> path;

  final List<Object> _pendingPath;
  final bool _complete;
  final bool _live;
  final bool _parentPending;

  // Whether the value was not finished when the document was last read.
  bool get _open {
    if (_complete || path.length > _pendingPath.length) return false;
    for (var i = 0; i < path.length; i++) {
      if (path[i] != _pendingPath[i]) return false;
    }
    return true;
  }

  /// Whether the value is still being written: more of it can arrive. For
  /// a map or list this is true until it is closed. False once the stream
  /// has failed or ended.
  bool get isPending => _live && _open;

  /// Whether the value is finished and will not change.
  bool get isDone => exists && !_open;

  /// Whether the value is missing but can still arrive: the map or list it
  /// belongs to is still being written, or the document has not started.
  bool get isAwaited =>
      !exists && (_parentPending || (path.isEmpty && _live && !_complete));

  /// The value under [key] of a map (a [String]) or at an index of a list
  /// (an [int]). Anything else, or a key that is not there, gives a value
  /// that does not exist.
  StructuredValue operator [](Object key) {
    final raw = this.raw;
    final childPath = [...path, key];
    final parentPending = exists ? isPending : isAwaited;
    if (raw is Map && key is String && raw.containsKey(key)) {
      return _child(raw[key], childPath);
    }
    if (raw is List && key is int && key >= 0 && key < raw.length) {
      return _child(raw[key], childPath);
    }
    return StructuredValue._(
      null,
      false,
      childPath,
      _pendingPath,
      _complete,
      _live,
      parentPending,
    );
  }

  StructuredValue _child(Object? value, List<Object> childPath) =>
      StructuredValue._(
        value,
        true,
        childPath,
        _pendingPath,
        _complete,
        _live,
        false,
      );

  /// The text of a string, or null for anything else.
  String? get asString {
    final raw = this.raw;
    return raw is String ? raw : null;
  }

  /// The number, or null for anything else. A number still being written
  /// gives its digits so far.
  num? get asNum {
    final raw = this.raw;
    return raw is num ? raw : null;
  }

  /// The number as an int when it is a whole number, or null.
  int? get asInt {
    final raw = this.raw;
    if (raw is int) return raw;
    if (raw is double && raw.isFinite && raw == raw.truncateToDouble()) {
      return raw.toInt();
    }
    return null;
  }

  /// The number as a double, or null for anything else.
  double? get asDouble => asNum?.toDouble();

  /// The bool, or null for anything else.
  bool? get asBool {
    final raw = this.raw;
    return raw is bool ? raw : null;
  }

  /// The items of a list so far, or an empty list for anything else.
  List<StructuredValue> get asList {
    final raw = this.raw;
    if (raw is! List) return const [];
    return [for (var i = 0; i < raw.length; i++) this[i]];
  }

  /// The entries of a map so far, in the order they arrived, or an empty
  /// map for anything else.
  Map<String, StructuredValue> get asMap {
    final raw = this.raw;
    if (raw is! Map) return const {};
    return {
      for (final key in raw.keys)
        if (key is String) key: this[key],
    };
  }

  /// Whether the value is a map.
  bool get isMap => raw is Map;

  /// Whether the value is a list.
  bool get isList => raw is List;

  /// Whether the value is a JSON `null` (and not just missing).
  bool get isNull => exists && raw == null;

  /// Whether the value is a string, number, bool or null: not a map or
  /// list, and not missing.
  bool get isScalar => exists && raw is! Map && raw is! List;

  /// The number of items of a list or entries of a map so far; 0 for
  /// anything else.
  int get length {
    final raw = this.raw;
    return switch (raw) {
      List() => raw.length,
      Map() => raw.length,
      _ => 0,
    };
  }

  @override
  String toString() {
    final state = !exists
        ? (isAwaited ? 'missing, awaited' : 'missing')
        : (isPending ? 'pending' : (isDone ? 'done' : 'unfinished'));
    return 'StructuredValue(${path.join('.')}: $raw, $state)';
  }
}
