import 'package:flutter/foundation.dart';

import 'package:llm_markdown_parser/llm_markdown_parser.dart';

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
  String _thinking = '';
  Object? _error;
  bool _paused = false;
  int _skips = 0;
  int _replays = 0;
  StackTrace? _stackTrace;

  /// All Markdown received so far.
  ///
  /// This is also the text to copy when the user copies the whole reply.
  String get text => _text;

  /// Whether the reply has ended.
  bool get isComplete => _isComplete;

  /// The error that ended the reply, if it ended with one.
  Object? get error => _error;

  /// Where [error] happened, when known.
  StackTrace? get stackTrace => _stackTrace;

  /// The reply without Markdown marks, for copying as plain text.
  String get plainText => markdownToPlainText(_text);

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

  /// The model's reasoning, for APIs that send it apart from the answer.
  ///
  /// Replies that start with `<think>...</think>` don't need this; the tags
  /// are picked up from [text].
  String get thinking => _thinking;

  /// Adds [chunk] to [thinking].
  void appendThinking(String chunk) {
    if (_isComplete) {
      throw StateError(
        'Cannot append to a completed StreamingMarkdownController. '
        'Call reset() to start a new reply.',
      );
    }
    if (chunk.isEmpty) return;
    _thinking += chunk;
    notifyListeners();
  }

  /// Marks the reply as ended.
  void complete() {
    if (_isComplete) return;
    _isComplete = true;
    notifyListeners();
  }

  /// Whether revealing the text is paused; see [pause].
  bool get isPaused => _paused;

  /// How often [skipAnimation] was called; widgets compare it to react.
  int get skipCount => _skips;

  /// How often [replay] was called; widgets compare it to react.
  int get replayCount => _replays;

  /// Stops revealing text. Text keeps arriving and is shown on [resume].
  void pause() {
    if (_paused) return;
    _paused = true;
    notifyListeners();
  }

  /// Continues revealing text after [pause].
  void resume() {
    if (!_paused) return;
    _paused = false;
    notifyListeners();
  }

  /// Shows everything that has arrived at once, skipping the reveal.
  void skipAnimation() {
    _skips++;
    notifyListeners();
  }

  /// Reveals the reply again from the start, for example after the user
  /// scrolled back to an old message.
  void replay() {
    _replays++;
    notifyListeners();
  }

  /// Ends the reply because of [error], for example a dropped connection.
  ///
  /// The text received so far stays; `StreamingMarkdown.errorBuilder` can
  /// show a message or a retry button below it.
  void completeWithError(Object error, [StackTrace? stackTrace]) {
    if (_isComplete) return;
    _error = error;
    _stackTrace = stackTrace;
    _isComplete = true;
    notifyListeners();
  }

  /// Replaces the text with [text], for example to start a new reply.
  ///
  /// A replaced text is shown at once, without smoothing.
  void reset([String text = '', bool isComplete = false]) {
    _text = text;
    _isComplete = isComplete;
    _thinking = '';
    _error = null;
    _stackTrace = null;
    _generation++;
    notifyListeners();
  }

  /// Appends every chunk of [stream] and completes when it is done.
  ///
  /// Stops early, without completing, if [reset] is called meanwhile. An
  /// error in [stream] ends the reply with [completeWithError] and is then
  /// rethrown.
  Future<void> addStream(Stream<String> stream) async {
    final generation = _generation;
    try {
      await for (final chunk in stream) {
        if (_generation != generation) return;
        append(chunk);
      }
    } on Object catch (error, stackTrace) {
      if (_generation == generation) completeWithError(error, stackTrace);
      rethrow;
    }
    if (_generation == generation) complete();
  }
}
