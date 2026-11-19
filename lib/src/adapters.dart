import 'dart:async';
import 'dart:convert';

import 'package:llm_markdown_parser/llm_markdown_parser.dart';

import 'controller.dart';

// Null for a line that isn't a JSON object: a keep-alive such as "ping",
// or an event cut short because the connection dropped. Neither is a reason
// to throw away the reply so far.
Map<String, dynamic>? _json(String data) {
  try {
    final json = jsonDecode(data);
    return json is Map<String, dynamic> ? json : null;
  } on FormatException {
    return null;
  }
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
        final json = _json(event.data);
        if (json == null) return false;
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
        final json = _json(event.data);
        if (json == null) return false;
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
