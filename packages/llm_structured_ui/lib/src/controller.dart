import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:partial_json/partial_json.dart';

import 'value.dart';

/// Takes the pieces of a JSON document as a model writes it and tells its
/// listeners after each piece.
///
/// ```dart
/// final controller = StructuredStreamController();
/// controller.addStream(modelTextStream);
/// // or: controller.add(chunk) for each piece, then controller.close()
/// ```
///
/// JSON that is wrong, and a document that ends in the middle, do not
/// throw: [error] is set, and [value] keeps what was read before it.
class StructuredStreamController extends ChangeNotifier {
  /// A controller. With [repair], common mistakes in model JSON are read
  /// anyway: single quotes, keys without quotes, comments, and Python's
  /// `True`, `False` and `None`.
  StructuredStreamController({this.repair = false})
    : _parser = PartialJsonParser(repair: repair);

  /// Whether common mistakes in model JSON are read anyway.
  final bool repair;

  PartialJsonParser _parser;
  Object? _error;
  bool _closed = false;
  bool _disposed = false;
  StreamSubscription<String>? _subscription;
  Completer<void>? _streamDone;

  /// The value so far: a map, list, string, number, bool or null. Null
  /// before the document has started.
  ///
  /// Maps and lists are updated in place as more arrives; copy them to
  /// keep an earlier state.
  Object? get value => _parser.hasValue ? _parser.value : null;

  /// Whether the document has started, so [value] means something.
  bool get hasValue => _parser.hasValue;

  /// Whether the JSON document is whole.
  bool get isComplete => _parser.isComplete;

  /// Whether [close] was called (or the stream given to [addStream]
  /// ended).
  bool get isClosed => _closed;

  /// The path of the value still being written, such as
  /// `['steps', 2, 'text']`. Empty when the document is complete or the
  /// outermost value is the one being written.
  List<Object> get pendingPath => _parser.pendingPath;

  /// What went wrong, or null: a [FormatException] for JSON that is wrong
  /// or ended in the middle, or the error of the stream given to
  /// [addStream]. Once set, further pieces are ignored until [reset].
  Object? get error => _error;

  /// A read helper for [value] as it is now. Take a new one after each
  /// change.
  StructuredValue get data => StructuredValue.root(
    value,
    exists: hasValue,
    pendingPath: pendingPath,
    isComplete: isComplete,
    isLive: _error == null && !_closed && !isComplete,
  );

  /// Adds the next piece of the document.
  ///
  /// Ignored after an [error]. Throws a [StateError] after [close]; call
  /// [reset] to start a new document.
  void add(String chunk) {
    if (_closed) {
      throw StateError('add() was called after close(); call reset() first.');
    }
    if (_error != null) return;
    try {
      _parser.add(chunk);
    } on FormatException catch (e) {
      _error = e;
      _stopReading();
    }
    notifyListeners();
  }

  /// Says that no more pieces will come. If the document is not whole,
  /// [error] is set to a [FormatException].
  void close() {
    if (_closed) return;
    _closed = true;
    if (_error == null) {
      try {
        _parser.close();
      } on FormatException catch (e) {
        _error = e;
      }
    }
    _stopReading();
    notifyListeners();
  }

  /// Forgets the document and any error, ready for a new one. A stream
  /// given to [addStream] is no longer read, and its future completes.
  void reset() {
    _stopReading();
    _parser = PartialJsonParser(repair: repair);
    _error = null;
    _closed = false;
    notifyListeners();
  }

  /// Reads [stream] into this controller: each event is [add]ed, and the
  /// end of the stream calls [close].
  ///
  /// The future completes when reading stops: at the end of the stream, on
  /// the first error (wrong JSON or an error of the stream, kept in
  /// [error]), or when [reset], [close] or another [addStream] is called.
  /// It never completes with an error.
  Future<void> addStream(Stream<String> stream) {
    _stopReading();
    final done = Completer<void>();
    _streamDone = done;
    _subscription = stream.listen(
      add,
      onError: (Object error) {
        _error ??= error;
        _stopReading();
        notifyListeners();
      },
      onDone: close,
    );
    return done.future;
  }

  void _stopReading() {
    final subscription = _subscription;
    final done = _streamDone;
    _subscription = null;
    _streamDone = null;
    subscription?.cancel();
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _stopReading();
    _disposed = true;
    super.dispose();
  }
}
