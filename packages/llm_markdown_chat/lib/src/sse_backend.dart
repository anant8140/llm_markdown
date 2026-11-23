import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_markdown/llm_markdown.dart';
import 'package:server_sent_events/server_sent_events.dart';

import 'chat_controller.dart';

/// Makes the body of a request from the [messages] to send, oldest first;
/// the last one is the new prompt. A `Map` or `List` is sent as JSON, a
/// `String` or bytes as they are.
typedef SseBodyBuilder = FutureOr<Object?> Function(List<ChatMessage> messages);

/// Takes the text of a reply out of the events of a response, for example
/// `(events) => events.anthropicText()`.
typedef SseTextExtractor = Stream<String> Function(Stream<SseEvent> events);

/// Gets replies from a streaming HTTP endpoint that answers with
/// server-sent events, through `package:server_sent_events`.
///
/// ```dart
/// final backend = SseChatBackend(
///   url: Uri.parse('https://api.openai.com/v1/chat/completions'),
///   headers: {'Authorization': 'Bearer $apiKey'},
///   body: SseChatBackend.openAIBody(model: 'gpt-4.1-mini'),
/// );
/// final chat = LlmChatController(onReply: backend.call);
/// ```
///
/// `LlmChatController.sse` does the same in one step and also sends the
/// attachments of the new prompt to [body].
class SseChatBackend {
  /// A backend that sends requests to [url].
  SseChatBackend({
    required this.url,
    required this.body,
    this.headers = const {},
    SseTextExtractor? text,
    this.method = 'POST',
    this.client,
    this.connectTimeout,
    this.idleTimeout,
  }) : text = text ?? _openAIText;

  /// The body for an OpenAI Chat Completions request (and the APIs that
  /// follow it): `model`, `stream: true` and the messages as `role` and
  /// `content`, after a [system] message if given. [extra] adds or
  /// replaces fields, such as `temperature`.
  static SseBodyBuilder openAIBody({
    required String model,
    String? system,
    Map<String, Object?> extra = const {},
  }) =>
      (messages) => {
        'model': model,
        'stream': true,
        'messages': [
          if (system != null) {'role': 'system', 'content': system},
          for (final message in messages)
            {'role': message.role.name, 'content': message.text},
        ],
        ...extra,
      };

  static Stream<String> _openAIText(Stream<SseEvent> events) =>
      events.openAIText();

  /// Where the requests go.
  final Uri url;

  /// Sent with each request, for example the `Authorization` header.
  final Map<String, String> headers;

  /// Makes the body of a request from the messages.
  final SseBodyBuilder body;

  /// Takes the text out of the events; OpenAI Chat Completions and
  /// Responses by default.
  final SseTextExtractor text;

  /// The HTTP method.
  final String method;

  /// The HTTP client to use, for example a `FakeSseClient` in tests; a new
  /// one for each request by default.
  final http.Client? client;

  /// Gives up on a server that does not answer in this time.
  final Duration? connectTimeout;

  /// Ends a response that sent nothing for this time.
  final Duration? idleTimeout;

  /// Sends [messages] and streams the answer into [reply].
  ///
  /// A failed request ends the reply with the `SseException`, which holds
  /// the status and the body the API sent; [chatErrorText] gives its
  /// message. When [reply] is completed meanwhile (the stop button), the
  /// request is aborted.
  Future<void> reply(
    List<ChatMessage> messages,
    StreamingMarkdownController reply,
  ) async {
    final content = await body(messages);
    // stopped while the body was made: no request
    if (reply.isComplete) return;
    final events = connectSse(
      url,
      method: method,
      headers: headers,
      body: content,
      client: client,
      connectTimeout: connectTimeout,
      idleTimeout: idleTimeout,
    );
    await reply.addStream(text(events));
  }

  /// This backend as the `onReply` of an `LlmChatController`.
  Future<void> call(
    String prompt,
    StreamingMarkdownController reply,
    List<ChatMessage> history,
  ) => this.reply([...history, ChatMessage.user(prompt)], reply);
}

/// The words to show for the [error] of a reply.
///
/// For an `SseException` this is the message in the body the API sent
/// (`{"error": {"message": "Invalid API key"}}` gives `Invalid API key`),
/// or the body itself, or the exception's message; for other errors their
/// text, without a leading `Exception: `.
String chatErrorText(Object error) {
  if (error is SseException) {
    final body = error.body?.trim() ?? '';
    if (body.isEmpty) return error.message;
    try {
      return _errorMessage(jsonDecode(body)) ?? body;
    } on FormatException {
      return body;
    }
  }
  final text = '$error';
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
}

String? _errorMessage(Object? json) {
  if (json is String) return json.isEmpty ? null : json;
  if (json is! Map) return null;
  return _errorMessage(json['error']) ??
      _errorMessage(json['message']) ??
      _errorMessage(json['detail']);
}
