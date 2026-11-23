import 'package:http/http.dart' as http;

import 'provider.dart';
import 'streaming.dart';
import 'types.dart';

/// Ollama's own chat API (`/api/chat`), which streams JSON Lines.
class OllamaProvider extends LlmProvider {
  /// A provider for the Ollama server at [baseUrl],
  /// `http://localhost:11434` by default.
  ///
  /// [headers] are added to every request, such as `Authorization` for a
  /// hosted server. Give [client] to reuse an [http.Client]; it is not
  /// closed by this class.
  OllamaProvider({
    String baseUrl = 'http://localhost:11434',
    this.headers = const {},
    http.Client? client,
  }) : baseUrl = Uri.parse(baseUrl),
       _client = client;

  /// The address of the server, without `/api`.
  final Uri baseUrl;

  /// Extra headers for every request.
  final Map<String, String> headers;

  final http.Client? _client;

  @override
  Stream<LlmEvent> stream(LlmRequest request) => decodeStream(
    open: () => postLines(
      url: url,
      headers: headers,
      body: buildBody(request),
      client: _client,
    ),
    decoder: _OllamaDecoder.new,
  );

  /// The address requests are sent to.
  Uri get url {
    final base = baseUrl.toString();
    return Uri.parse(
      '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}'
      '/api/chat',
    );
  }

  /// The JSON body sent for [request].
  Map<String, Object?> buildBody(LlmRequest request) {
    final options = {
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.maxTokens != null) 'num_predict': request.maxTokens,
    };
    return {
      'model': request.model,
      'messages': [
        for (final message in request.messages)
          switch (message.role) {
            LlmRole.system => {'role': 'system', 'content': message.text},
            LlmRole.user => {'role': 'user', 'content': message.text},
            LlmRole.assistant => {
              'role': 'assistant',
              'content': message.text,
              if (message.toolCalls.isNotEmpty)
                'tool_calls': [
                  for (final call in message.toolCalls)
                    {
                      // the arguments are an object here, not JSON text
                      'function': {
                        'name': call.name,
                        'arguments': call.arguments,
                      },
                    },
                ],
            },
            LlmRole.tool => {
              'role': 'tool',
              'content': message.text,
              if (toolNameFor(message, request.messages).isNotEmpty)
                'tool_name': toolNameFor(message, request.messages),
            },
          },
      ],
      'stream': true,
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            {
              'type': 'function',
              'function': {
                'name': tool.name,
                if (tool.description.isNotEmpty)
                  'description': tool.description,
                'parameters': tool.parameters,
              },
            },
        ],
      if (options.isNotEmpty) 'options': options,
      ...request.extra,
    };
  }
}

class _OllamaDecoder extends WireDecoder<String> {
  var _calls = 0;
  var _done = false;

  @override
  bool get isDone => _done;

  @override
  void add(String line, Emit emit) {
    if (line.trim().isEmpty) return;
    final json = decodeObject(line);
    throwIfError(json, line);

    final message = json['message'];
    if (message is Map) {
      final thinking = message['thinking'];
      if (thinking is String && thinking.isNotEmpty) {
        emit(LlmThinkingDelta(thinking));
      }
      final content = message['content'];
      if (content is String && content.isNotEmpty) emit(LlmTextDelta(content));
      final calls = message['tool_calls'];
      if (calls is List) {
        for (final call in calls) {
          final function = call is Map ? call['function'] : null;
          if (call is! Map || function is! Map) continue;
          // tool calls arrive whole; older servers send no ID
          final id = call['id'];
          emitWholeToolCall(
            emit,
            id: id is String && id.isNotEmpty ? id : 'call_$_calls',
            name: '${function['name'] ?? ''}',
            arguments: function['arguments'],
          );
          _calls++;
        }
      }
    }
    if (json['done'] != true) return;
    final input = _int(json['prompt_eval_count']);
    final output = _int(json['eval_count']);
    if (input != null || output != null) {
      emit(LlmUsage(inputTokens: input, outputTokens: output));
    }
    final reason = json['done_reason'];
    emit(
      LlmDone(switch (reason) {
        // a reply that calls tools also ends with `stop`
        'stop' || null when _calls > 0 => LlmFinishReason.toolCalls,
        'stop' || null => LlmFinishReason.stop,
        'length' => LlmFinishReason.length,
        _ => LlmFinishReason.other,
      }, rawFinishReason: reason is String ? reason : null),
    );
    _done = true;
  }
}

int? _int(Object? value) => value is num ? value.toInt() : null;
