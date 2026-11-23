/// Streams `llm_client` replies into a [StreamingMarkdownController].
///
/// ```dart
/// final provider = OpenAIProvider(apiKey: key);
/// final controller = StreamingMarkdownController();
/// controller.addLlmEvents(provider.stream(request));
/// ```
library;

import 'dart:async';

import 'package:llm_client/llm_client.dart';
import 'package:llm_markdown/llm_markdown.dart';

/// Reads `llm_client` events into a [StreamingMarkdownController].
extension LlmClientStreams on StreamingMarkdownController {
  /// Feeds the [events] of a reply, as `LlmProvider.stream` gives them, and
  /// completes the reply when they end.
  ///
  /// Text is appended, thinking goes to [appendThinking], and tool calls
  /// go to [toolCalls] with their arguments as they are written, so the
  /// reply shows a line such as "Using get weather  Paris" while the model
  /// is still writing them.
  ///
  /// An error ends the reply with [completeWithError] and is then rethrown.
  /// Calling [reset] or [complete] meanwhile (a stop button) stops reading
  /// at once and cancels [events], which aborts the request.
  ///
  /// [onEvent] sees every event, for usage counts or the finished tool
  /// calls an app has to run.
  Future<void> addLlmEvents(
    Stream<LlmEvent> events, {
    void Function(LlmEvent event)? onEvent,
  }) {
    final started = generation;
    final done = Completer<void>();
    late final StreamSubscription<LlmEvent> subscription;
    late final void Function() watch;

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
      if (generation != started || isComplete) finish();
    };

    void fail(Object error, StackTrace stackTrace) {
      if (done.isCompleted) return;
      // stop watching first: ending the reply here must not look like the
      // app ending it
      removeListener(watch);
      if (generation == started && !isComplete) {
        completeWithError(error, stackTrace);
      }
      finish(error, stackTrace);
    }

    addListener(watch);
    subscription = events.listen(
      (event) {
        if (done.isCompleted) return;
        try {
          switch (event) {
            case LlmTextDelta(:final text):
              append(text);
            case LlmThinkingDelta(:final text):
              appendThinking(text);
            case LlmToolCallStart(:final id, :final name):
              startToolCall(id, name);
            case LlmToolCallDelta(:final id, :final rawDelta):
              addToolCallArguments(id, rawDelta);
            case LlmToolCallDone(:final id):
              finishToolCall(id);
            case LlmUsage() || LlmDone():
              break;
          }
          onEvent?.call(event);
        } catch (error, stackTrace) {
          fail(error, stackTrace);
        }
      },
      onError: fail,
      onDone: () {
        if (done.isCompleted) return;
        removeListener(watch);
        complete();
        finish();
      },
    );
    return done.future;
  }
}
