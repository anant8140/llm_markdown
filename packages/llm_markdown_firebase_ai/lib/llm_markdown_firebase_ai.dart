/// Streams Firebase AI Logic replies into a [StreamingMarkdownController].
///
/// ```dart
/// final model = FirebaseAI.googleAI().generativeModel(model: 'gemini-2.5-flash');
/// final controller = StreamingMarkdownController();
/// controller.addFirebaseAIStream(model.generateContentStream(prompt));
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:llm_markdown/llm_markdown.dart';

/// Reads `firebase_ai` responses into a [StreamingMarkdownController].
extension FirebaseAIStreams on StreamingMarkdownController {
  /// Appends every response of [responses], such as
  /// `GenerativeModel.generateContentStream` or `ChatSession.sendMessageStream`
  /// gives, and completes the reply when the stream ends.
  ///
  /// Text parts are appended and thought summaries go to [appendThinking].
  /// Function calls go to [toolCalls], with their arguments as JSON, and the
  /// pages of Google Search grounding to [sources].
  ///
  /// A blocked prompt or reply ends it with [completeWithError] and a
  /// [ModelStreamError], as does an error in [responses]; the error is then
  /// rethrown. Calling [reset] or [complete] meanwhile (a stop button) stops
  /// reading at once and cancels [responses], which closes the request.
  Future<void> addFirebaseAIStream(Stream<GenerateContentResponse> responses) {
    // already stopped, for example while waiting for the first response
    if (isComplete) {
      unawaited(responses.listen(null).cancel());
      return Future.value();
    }
    final started = generation;
    final done = Completer<void>();
    var calls = 0;
    late final StreamSubscription<GenerateContentResponse> subscription;
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
      removeListener(watch);
      final shown = error is FirebaseAIException
          ? ModelStreamError(error.message)
          : error;
      if (generation == started && !isComplete) {
        completeWithError(shown, stackTrace);
      }
      finish(shown, stackTrace);
    }

    void read(GenerateContentResponse response) {
      final feedback = response.promptFeedback;
      final candidate = response.candidates.firstOrNull;
      if (candidate == null) {
        final reason = feedback?.blockReason;
        if (reason != null) {
          throw ModelStreamError(
            _blocked(reason.name, feedback?.blockReasonMessage),
          );
        }
        return;
      }
      final chunks = candidate.groundingMetadata?.groundingChunks;
      for (final chunk in chunks ?? const <GroundingChunk>[]) {
        final page = chunk.web;
        final place = chunk.maps;
        if (page != null) {
          addSource(MarkdownSource(url: page.uri, title: page.title));
        } else if (place != null) {
          addSource(MarkdownSource(url: place.uri, title: place.title));
        }
      }
      for (final part in candidate.content.parts) {
        switch (part) {
          case FunctionCall(:final id, :final name, :final args):
            final key = id ?? 'call_${calls++}';
            startToolCall(key, name);
            if (args.isNotEmpty) addToolCallArguments(key, jsonEncode(args));
            finishToolCall(key);
          case TextPart(:final text) when part.isThought == true:
            if (text.isNotEmpty) appendThinking(text);
          case TextPart(:final text):
            if (text.isNotEmpty) append(text);
          default:
        }
      }
      final reason = candidate.finishReason;
      if (reason != null && _blockedReasons.contains(reason.name)) {
        throw ModelStreamError(_blocked(reason.name, candidate.finishMessage));
      }
    }

    addListener(watch);
    subscription = responses.listen(
      (response) {
        if (done.isCompleted) return;
        try {
          read(response);
        } catch (error, stackTrace) {
          fail(error, stackTrace);
        }
      },
      onError: fail,
      onDone: () {
        if (done.isCompleted) return;
        removeListener(watch);
        if (generation == started) complete();
        finish();
      },
    );
    return done.future;
  }

  // by name, as newer firebase_ai versions add reasons
  static const _blockedReasons = {
    'safety',
    'recitation',
    'blocklist',
    'prohibitedContent',
    'spii',
    'malformedFunctionCall',
    'imageSafety',
    'imageProhibitedContent',
    'imageRecitation',
    'language',
    'unexpectedToolCall',
    'tooManyToolCalls',
    'malformedResponse',
  };

  static String _blocked(String reason, String? message) =>
      'Blocked: $reason'
      '${message != null && message.isNotEmpty ? ' ($message)' : ''}';
}
