import 'package:flutter/foundation.dart';

/// Holds Markdown text that arrives in pieces, such as an AI chat reply.
///
/// Call [append] for each piece and [complete] when the reply has ended.
/// A `StreamingMarkdown` widget listens to the controller and shows the
/// text as it grows.
///
/// ```dart
/// final controller = StreamingMarkdownController();
/// await for (final chunk in replyStream) {
///   controller.append(chunk);
/// }
/// controller.complete();
/// ```
class StreamingMarkdownController extends ChangeNotifier {
  /// Creates a controller that starts with [text].
  ///
  /// Pass `isComplete: true` for a reply that has already ended, such as a
  /// message loaded from history.
  StreamingMarkdownController({String text = '', bool isComplete = false})
    : _text = text,
      _isComplete = isComplete;

  String _text;
  bool _isComplete;
  int _generation = 0;

  /// All Markdown received so far.
  ///
  /// This is also the text to copy when the user copies the whole reply.
  String get text => _text;

  /// Whether the reply has ended.
  bool get isComplete => _isComplete;

  /// A number that changes each time [reset] replaces the text.
  ///
  /// Widgets use it to tell a replaced text from a text that grew.
  int get generation => _generation;

  /// Adds [chunk] to the end of the text.
  ///
  /// Throws a [StateError] after [complete]; call [reset] to start again.
  void append(String chunk) {
    if (_isComplete) {
      throw StateError(
        'Cannot append to a completed StreamingMarkdownController. '
        'Call reset() to start a new reply.',
      );
    }
    if (chunk.isEmpty) return;
    _text += chunk;
    notifyListeners();
  }

  /// Marks the reply as ended.
  void complete() {
    if (_isComplete) return;
    _isComplete = true;
    notifyListeners();
  }

  /// Replaces the text with [text], for example to start a new reply.
  ///
  /// A replaced text is shown at once, without smoothing.
  void reset([String text = '', bool isComplete = false]) {
    _text = text;
    _isComplete = isComplete;
    _generation++;
    notifyListeners();
  }

  /// Appends every chunk of [stream] and completes when it is done.
  ///
  /// Stops early, without completing, if [reset] is called meanwhile. An
  /// error in [stream] completes the reply and is then rethrown.
  Future<void> addStream(Stream<String> stream) async {
    final generation = _generation;
    try {
      await for (final chunk in stream) {
        if (_generation != generation) return;
        append(chunk);
      }
    } finally {
      if (_generation == generation) complete();
    }
  }
}
