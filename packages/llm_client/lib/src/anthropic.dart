import 'package:http/http.dart' as http;
import 'package:server_sent_events/server_sent_events.dart';

import 'provider.dart';
import 'streaming.dart';
import 'types.dart';

/// Anthropic's Messages API.
class AnthropicProvider extends LlmProvider {
  /// A provider using [apiKey], sent as `x-api-key`, and the API
  /// [version], sent as `anthropic-version`.
  ///
  /// The API needs `max_tokens` in every request: [defaultMaxTokens] is
  /// sent when [LlmRequest.maxTokens] is null. [headers] are added to
  /// every request, such as `anthropic-beta`. Give [client] to reuse an
  /// [http.Client]; it is not closed by this class.
  AnthropicProvider({
    required this.apiKey,
    this.version = '2023-06-01',
    String baseUrl = 'https://api.anthropic.com/v1',
    this.defaultMaxTokens = 4096,
    this.headers = const {},
    http.Client? client,
  }) : baseUrl = Uri.parse(baseUrl),
       _client = client;

  /// The API key.
  final String apiKey;

  /// The API version.
  final String version;

  /// The address of the API, up to and including `/v1`.
  final Uri baseUrl;

  /// The `max_tokens` sent when the request names none.
  final int defaultMaxTokens;

  /// Extra headers for every request.
  final Map<String, String> headers;

  final http.Client? _client;

  @override
  Stream<LlmEvent> stream(LlmRequest request) => sseStream(
    url: url,
    headers: {'x-api-key': apiKey, 'anthropic-version': version, ...headers},
    body: buildBody(request),
    client: _client,
    decoder: _AnthropicDecoder.new,
  );

  /// The address requests are sent to.
  Uri get url {
    final base = baseUrl.toString();
    return Uri.parse(
      '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}'
      '/messages',
    );
  }

  /// The JSON body sent for [request].
  Map<String, Object?> buildBody(LlmRequest request) {
    final system = [
      for (final message in request.messages)
        if (message.role == LlmRole.system && message.text.isNotEmpty)
          message.text,
    ];
    final messages = <Map<String, Object?>>[];
    for (final message in request.messages) {
      switch (message.role) {
        case LlmRole.system:
          break;
        case LlmRole.user:
          messages.add({'role': 'user', 'content': message.text});
        case LlmRole.assistant:
          messages.add({
            'role': 'assistant',
            'content': message.toolCalls.isEmpty
                ? message.text
                : [
                    if (message.text.isNotEmpty)
                      {'type': 'text', 'text': message.text},
                    for (final call in message.toolCalls)
                      {
                        'type': 'tool_use',
                        'id': call.id,
                        'name': call.name,
                        'input': call.arguments,
                      },
                  ],
          });
        case LlmRole.tool:
          final result = {
            'type': 'tool_result',
            'tool_use_id': message.toolCallId,
            'content': message.text,
          };
          // the results of one turn go in one user message
          final last = messages.isEmpty ? null : messages.last;
          final content = last?['content'];
          if (last != null &&
              last['role'] == 'user' &&
              content is List &&
              content.every((b) => b is Map && b['type'] == 'tool_result')) {
            content.add(result);
          } else {
            messages.add({
              'role': 'user',
              'content': <Object?>[result],
            });
          }
      }
    }
    return {
      'model': request.model,
      'max_tokens': request.maxTokens ?? defaultMaxTokens,
      if (system.isNotEmpty) 'system': system.join('\n\n'),
      'messages': messages,
      'stream': true,
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            {
              'name': tool.name,
              if (tool.description.isNotEmpty) 'description': tool.description,
              'input_schema': tool.parameters,
            },
        ],
      if (request.temperature != null) 'temperature': request.temperature,
      ...request.extra,
    };
  }
}

class _AnthropicDecoder extends WireDecoder<SseEvent> {
  // tool calls by the index of their content block
  final _calls = <int, ToolCallBuilder>{};
  int? _inputTokens;
  int? _outputTokens;
  String? _stop;
  var _done = false;

  @override
  bool get isDone => _done;

  @override
  void add(SseEvent event, Emit emit) {
    if (event.data.trim().isEmpty) return;
    final json = decodeObject(event.data);
    final type = json['type'] ?? event.event;
    switch (type) {
      case 'error':
        throwIfError(json, event.data);
        throw LlmException('The provider reported an error', body: event.data);
      case 'message_start':
        final message = json['message'];
        if (message is Map) _readUsage(message['usage']);
      case 'content_block_start':
        final block = json['content_block'];
        if (block is! Map) return;
        switch (block['type']) {
          case 'tool_use':
            final builder = ToolCallBuilder(
              '${block['id'] ?? 'call_${_calls.length}'}',
              '${block['name'] ?? ''}',
            );
            _calls[_int(json['index']) ?? 0] = builder;
            emit(builder.start());
          // a block may start with content, though the API starts empty
          case 'text':
            final text = block['text'];
            if (text is String && text.isNotEmpty) emit(LlmTextDelta(text));
          case 'thinking':
            final text = block['thinking'];
            if (text is String && text.isNotEmpty) {
              emit(LlmThinkingDelta(text));
            }
        }
      case 'content_block_delta':
        final delta = json['delta'];
        if (delta is! Map) return;
        switch (delta['type']) {
          case 'text_delta':
            final text = delta['text'];
            if (text is String && text.isNotEmpty) emit(LlmTextDelta(text));
          case 'thinking_delta':
            final text = delta['thinking'];
            if (text is String && text.isNotEmpty) {
              emit(LlmThinkingDelta(text));
            }
          case 'input_json_delta':
            final piece = delta['partial_json'];
            final builder = _calls[_int(json['index']) ?? 0];
            if (builder != null && piece is String && piece.isNotEmpty) {
              emit(builder.add(piece));
            }
        }
      case 'content_block_stop':
        final builder = _calls.remove(_int(json['index']) ?? 0);
        if (builder != null) emit(builder.done());
      case 'message_delta':
        final delta = json['delta'];
        if (delta is Map && delta['stop_reason'] is String) {
          _stop = delta['stop_reason'] as String;
        }
        _readUsage(json['usage']);
      case 'message_stop':
        if (_inputTokens != null || _outputTokens != null) {
          emit(
            LlmUsage(inputTokens: _inputTokens, outputTokens: _outputTokens),
          );
        }
        emit(
          LlmDone(switch (_stop) {
            'end_turn' || 'stop_sequence' || null => LlmFinishReason.stop,
            'max_tokens' => LlmFinishReason.length,
            'tool_use' => LlmFinishReason.toolCalls,
            'refusal' => LlmFinishReason.contentFilter,
            _ => LlmFinishReason.other,
          }, rawFinishReason: _stop),
        );
        _done = true;
      // `ping` and event types added later are skipped
    }
  }

  void _readUsage(Object? usage) {
    if (usage is! Map) return;
    _inputTokens = _int(usage['input_tokens']) ?? _inputTokens;
    _outputTokens = _int(usage['output_tokens']) ?? _outputTokens;
  }
}

int? _int(Object? value) => value is num ? value.toInt() : null;
