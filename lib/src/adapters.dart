import 'dart:async';
import 'dart:convert';

import 'controller.dart';

/// One event of a server-sent events (SSE) stream.
class ServerSentEvent {
  /// Creates an event.
  const ServerSentEvent(this.data, {this.event});

  /// The `event:` field, or null for the default "message" event.
  final String? event;

  /// The `data:` lines, joined with newlines.
  final String data;
}

/// Splits the raw bytes of an HTTP response body into server-sent events.
///
/// Works with any HTTP client that exposes the body as a byte stream, e.g.
/// `StreamedResponse.stream` from `package:http`.
Stream<ServerSentEvent> serverSentEvents(Stream<List<int>> bytes) async* {
  String? event;
  final data = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield ServerSentEvent(data.join('\n'), event: event);
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') event = value;
    if (field == 'data') data.add(value);
  }
  if (data.isNotEmpty) yield ServerSentEvent(data.join('\n'), event: event);
}

/// Error from a model API, sent inside its event stream.
class ModelStreamError implements Exception {
  /// Creates an error with the API's [message].
  const ModelStreamError(this.message);

  /// What the API reported.
  final String message;

  @override
  String toString() => 'ModelStreamError: $message';
}

/// Feeds the event streams of common model APIs into a controller.
extension ModelStreams on StreamingMarkdownController {
  /// Reads an OpenAI-style streaming response body and completes the reply.
  ///
  /// Handles Chat Completions chunks (`choices[0].delta.content`, and the
  /// `reasoning_content` / `reasoning` fields some providers add) and the
  /// Responses API events (`response.output_text.delta` and reasoning
  /// summaries). Reasoning goes to [appendThinking].
  Future<void> addOpenAIStream(Stream<List<int>> bytes) =>
      _feed(bytes, (event) {
        if (event.data == '[DONE]') return true;
        final json = jsonDecode(event.data);
        if (json is! Map<String, dynamic>) return false;
        final error = json['error'];
        if (error != null) throw ModelStreamError(_message(error));
        switch (json['type']) {
          case 'response.output_text.delta':
            _add(json['delta']);
          case 'response.reasoning_summary_text.delta' ||
              'response.reasoning_text.delta':
            _addThinking(json['delta']);
          case 'response.completed':
            return true;
          case 'response.failed' || 'error':
            throw ModelStreamError(_message(json['response'] ?? json));
        }
        final choices = json['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final delta = (choices.first as Map)['delta'];
          if (delta is Map) {
            _addThinking(delta['reasoning_content'] ?? delta['reasoning']);
            _add(delta['content']);
          }
        }
        return false;
      });

  /// Reads an Anthropic Messages API streaming response body and completes
  /// the reply. Text deltas are appended, thinking deltas go to
  /// [appendThinking].
  Future<void> addAnthropicStream(Stream<List<int>> bytes) =>
      _feed(bytes, (event) {
        final json = jsonDecode(event.data);
        if (json is! Map<String, dynamic>) return false;
        switch (json['type']) {
          case 'content_block_delta':
            final delta = json['delta'];
            if (delta is Map) {
              if (delta['type'] == 'text_delta') _add(delta['text']);
              if (delta['type'] == 'thinking_delta') {
                _addThinking(delta['thinking']);
              }
            }
          case 'message_stop':
            return true;
          case 'error':
            throw ModelStreamError(_message(json['error'] ?? json));
        }
        return false;
      });

  void _add(Object? text) {
    if (text is String && text.isNotEmpty) append(text);
  }

  void _addThinking(Object? text) {
    if (text is String && text.isNotEmpty) appendThinking(text);
  }

  static String _message(Object? error) {
    if (error is Map) {
      final message = error['message'] ?? error['error'];
      if (message != null) return _message(message);
    }
    return '$error';
  }

  // Calls [onEvent] for each event until it returns true or the stream ends,
  // then completes. Errors end the reply with completeWithError and are
  // rethrown. Stops quietly if the controller is reset meanwhile.
  Future<void> _feed(
    Stream<List<int>> bytes,
    bool Function(ServerSentEvent event) onEvent,
  ) async {
    final started = generation;
    try {
      await for (final event in serverSentEvents(bytes)) {
        if (generation != started) return;
        if (onEvent(event)) break;
      }
    } on Object catch (error, stackTrace) {
      if (generation == started) completeWithError(error, stackTrace);
      rethrow;
    }
    if (generation == started) complete();
  }
}
