import 'dart:async';
import 'dart:collection';

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

  /// Marks the reply as ended. Tool calls still running are marked done.
  void complete() {
    if (_isComplete) return;
    _isComplete = true;
    _finishToolCalls();
    notifyListeners();
  }

  /// The pages and documents the model cited, in the order they were first
  /// cited. Source `n` is `sources[n - 1]`, so a `[n]` chip given to
  /// `StreamingMarkdown.onCitationTap` can be looked up here.
  ///
  /// `addAnthropicStream` puts `[n]` after the text each source supports;
  /// `addOpenAIStream` and `addGeminiStream` only fill this list, since
  /// their text already carries links or no marks at all.
  List<MarkdownSource> get sources => _sourcesView;
  final List<MarkdownSource> _sources = [];
  late final List<MarkdownSource> _sourcesView = UnmodifiableListView(_sources);

  /// Adds [source] to [sources] and returns its number, starting at 1. A
  /// source with the same address (or, without one, the same title) that is
  /// already there keeps its number.
  int addSource(MarkdownSource source) {
    final known = _sources.indexWhere((other) => other._sameAs(source));
    if (known != -1) return known + 1;
    _sources.add(source);
    notifyListeners();
    return _sources.length;
  }

  /// The tools the model called during this reply, such as a web search
  /// or one of your functions, in order. `StreamingMarkdown` shows them at
  /// the top of the reply, wherever in the reply they were made; see
  /// `StreamingMarkdown.toolCallBuilder`.
  List<MarkdownToolCall> get toolCalls => _toolCallsView;
  final List<MarkdownToolCall> _toolCalls = [];
  late final List<MarkdownToolCall> _toolCallsView = UnmodifiableListView(
    _toolCalls,
  );

  /// Records that the model started calling the tool [name]; [id] tells
  /// calls apart. Calling it again for a known [id] only fills in a name
  /// that was empty.
  void startToolCall(String id, String name) {
    final i = _toolCalls.indexWhere((call) => call.id == id);
    if (i == -1) {
      _toolCalls.add(MarkdownToolCall(id: id, name: name));
    } else if (_toolCalls[i].name.isEmpty && name.isNotEmpty) {
      _toolCalls[i] = _toolCalls[i]._copy(name: name);
    } else {
      return;
    }
    notifyListeners();
  }

  /// Adds [chunk] to the arguments of the tool call [id], which are JSON
  /// text that arrives in pieces.
  void addToolCallArguments(String id, String chunk) {
    final i = _toolCalls.indexWhere((call) => call.id == id);
    if (i == -1 || chunk.isEmpty) return;
    _toolCalls[i] = _toolCalls[i]._copy(
      arguments: _toolCalls[i].arguments + chunk,
    );
    notifyListeners();
  }

  /// Marks the tool call [id] as finished.
  void finishToolCall(String id) {
    final i = _toolCalls.indexWhere((call) => call.id == id);
    if (i == -1 || _toolCalls[i].isDone) return;
    _toolCalls[i] = _toolCalls[i]._copy(isDone: true);
    notifyListeners();
  }

  void _finishToolCalls() {
    for (var i = 0; i < _toolCalls.length; i++) {
      if (!_toolCalls[i].isDone) {
        _toolCalls[i] = _toolCalls[i]._copy(isDone: true);
      }
    }
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
    _finishToolCalls();
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
    _sources.clear();
    _toolCalls.clear();
    _error = null;
    _stackTrace = null;
    _generation++;
    notifyListeners();
  }

  /// Appends every chunk of [stream] and completes when it is done.
  ///
  /// Stops at once, without completing, if [reset] is called meanwhile, and
  /// also if [complete] is (a stop button): [stream] is then cancelled,
  /// which closes the request behind it. An error in [stream] ends the
  /// reply with [completeWithError] and is then rethrown.
  Future<void> addStream(Stream<String> stream) {
    final started = _generation;
    final done = Completer<void>();
    late final StreamSubscription<String> subscription;
    late final VoidCallback watch;

    void finish([Object? error, StackTrace? stackTrace]) {
      if (done.isCompleted) return;
      removeListener(watch);
      unawaited(subscription.cancel());
      if (error == null) {
        done.complete();
      } else {
        done.completeError(error, stackTrace);
      }
    }

    watch = () {
      if (_generation != started || _isComplete) finish();
    };
    subscription = stream.listen(
      (chunk) {
        if (!done.isCompleted) append(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (done.isCompleted) return;
        removeListener(watch);
        if (_generation == started) completeWithError(error, stackTrace);
        finish(error, stackTrace);
      },
      onDone: () {
        if (done.isCompleted) return;
        removeListener(watch);
        if (_generation == started) complete();
        finish();
      },
      cancelOnError: true,
    );
    addListener(watch);
    return done.future;
  }
}

/// A web page or document the model cited; see
/// [StreamingMarkdownController.sources].
@immutable
class MarkdownSource {
  /// Creates a source; any part may be missing.
  const MarkdownSource({this.url, this.title, this.citedText});

  /// The address of the page, when it has one.
  final String? url;

  /// The title of the page or document.
  final String? title;

  /// The words of the source the model relied on, when the API says.
  final String? citedText;

  // the same page, or the same titled document; sources with neither are
  // never taken for each other
  bool _sameAs(MarkdownSource other) => url != null || other.url != null
      ? url == other.url
      : title != null && title == other.title;

  @override
  bool operator ==(Object other) =>
      other is MarkdownSource &&
      other.url == url &&
      other.title == title &&
      other.citedText == citedText;

  @override
  int get hashCode => Object.hash(url, title, citedText);

  @override
  String toString() => 'MarkdownSource(${url ?? title})';
}

/// A tool the model called, such as a web search or one of your functions;
/// see [StreamingMarkdownController.toolCalls].
@immutable
class MarkdownToolCall {
  /// Creates a record of a tool call.
  const MarkdownToolCall({
    required this.id,
    required this.name,
    this.arguments = '',
    this.isDone = false,
  });

  /// Tells calls apart; given by the API.
  final String id;

  /// The tool's name, such as `web_search` or `get_weather`.
  final String name;

  /// The arguments as JSON text, possibly not complete yet.
  final String arguments;

  /// Whether the call has finished.
  final bool isDone;

  MarkdownToolCall _copy({String? name, String? arguments, bool? isDone}) =>
      MarkdownToolCall(
        id: id,
        name: name ?? this.name,
        arguments: arguments ?? this.arguments,
        isDone: isDone ?? this.isDone,
      );

  @override
  bool operator ==(Object other) =>
      other is MarkdownToolCall &&
      other.id == id &&
      other.name == name &&
      other.arguments == arguments &&
      other.isDone == isDone;

  @override
  int get hashCode => Object.hash(id, name, arguments, isDone);

  @override
  String toString() => 'MarkdownToolCall($name${isDone ? ', done' : ''})';
}
