import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:server_sent_events/server_sent_events.dart';

import 'provider.dart';
import 'streaming.dart';
import 'types.dart';

/// OpenAI's Chat Completions API, and servers that speak it: give their
/// address as [baseUrl].
class OpenAIProvider extends LlmProvider {
  /// A provider for the API at [baseUrl], `https://api.openai.com/v1` by
  /// default. The request goes to `<baseUrl>/chat/completions`.
  ///
  /// [apiKey] is sent as a bearer token; leave it out for a local server
  /// that needs none. [headers] are added to every request. Give [client]
  /// to reuse an [http.Client]; it is not closed by this class.
  OpenAIProvider({
    this.apiKey,
    String baseUrl = 'https://api.openai.com/v1',
    this.headers = const {},
    this.maxTokensField = 'max_completion_tokens',
    this.includeUsage = true,
    http.Client? client,
  }) : baseUrl = Uri.parse(baseUrl),
       _client = client;

  /// The API key, or null for none.
  final String? apiKey;

  /// The address of the API, up to and including the version (`/v1`).
  final Uri baseUrl;

  /// Extra headers for every request, such as `OpenAI-Organization`.
  final Map<String, String> headers;

  /// The body field [LlmRequest.maxTokens] is sent as. OpenAI's name is
  /// `max_completion_tokens`; some compatible servers only know the older
  /// `max_tokens`.
  final String maxTokensField;

  /// Whether to ask for token counts with
  /// `stream_options: {include_usage: true}`. Turn it off for a server
  /// that rejects the field.
  final bool includeUsage;

  final http.Client? _client;

  @override
  Stream<LlmEvent> stream(LlmRequest request) => sseStream(
    url: url,
    headers: {
      if (apiKey != null && apiKey!.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
      ...headers,
    },
    body: buildBody(request),
    client: _client,
    decoder: _OpenAIDecoder.new,
  );

  /// The address requests are sent to.
  Uri get url {
    final base = baseUrl.toString();
    return Uri.parse(
      '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}'
      '/chat/completions',
    );
  }

  /// The JSON body sent for [request].
  Map<String, Object?> buildBody(LlmRequest request) => {
    'model': request.model,
    'messages': [for (final message in request.messages) _message(message)],
    'stream': true,
    if (includeUsage) 'stream_options': {'include_usage': true},
    if (request.tools.isNotEmpty)
      'tools': [
        for (final tool in request.tools)
          {
            'type': 'function',
            'function': {
              'name': tool.name,
              if (tool.description.isNotEmpty) 'description': tool.description,
              'parameters': tool.parameters,
            },
          },
      ],
    if (request.temperature != null) 'temperature': request.temperature,
    if (request.maxTokens != null) maxTokensField: request.maxTokens,
    ...request.extra,
  };

  Map<String, Object?> _message(LlmMessage message) => switch (message.role) {
    LlmRole.system => {'role': 'system', 'content': message.text},
    LlmRole.user => {'role': 'user', 'content': message.text},
    LlmRole.assistant => {
      'role': 'assistant',
      // no text next to tool calls is sent as null
      'content': message.text.isEmpty && message.toolCalls.isNotEmpty
          ? null
          : message.text,
      if (message.toolCalls.isNotEmpty)
        'tool_calls': [
          for (final call in message.toolCalls)
            {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': jsonEncode(call.arguments),
              },
            },
        ],
    },
    LlmRole.tool => {
      'role': 'tool',
      'tool_call_id': message.toolCallId,
      'content': message.text,
    },
  };
}

class _OpenAIDecoder extends WireDecoder<SseEvent> {
  // tool calls by their `index` in the chunk
  final _calls = <int, ToolCallBuilder>{};
  final _open = <int>[];
  // argument pieces that came before the call's name
  final _early = <int, StringBuffer>{};
  final _ids = <int, String>{};
  int? _last;
  LlmUsage? _usage;
  String? _finish;
  var _sawFinish = false;
  var _sawToolCalls = false;
  var _done = false;

  @override
  bool get isDone => _done;

  @override
  void add(SseEvent event, Emit emit) {
    if (event.isDone) {
      _end(emit);
      return;
    }
    if (event.data.trim().isEmpty) return;
    final json = decodeObject(event.data);
    throwIfError(json, event.data);

    final usage = json['usage'];
    if (usage is Map) {
      _usage = LlmUsage(
        inputTokens: _int(usage['prompt_tokens']),
        outputTokens: _int(usage['completion_tokens']),
      );
    }
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) return;
    final choice = choices.first;
    if (choice is! Map) return;
    final delta = choice['delta'];
    if (delta is Map) {
      // not from OpenAI itself: DeepSeek, vLLM and others send the
      // model's reasoning under one of these names
      final thinking = delta['reasoning_content'] ?? delta['reasoning'];
      if (thinking is String && thinking.isNotEmpty) {
        emit(LlmThinkingDelta(thinking));
      }
      final content = delta['content'];
      if (content is String && content.isNotEmpty) emit(LlmTextDelta(content));
      final calls = delta['tool_calls'];
      if (calls is List) {
        for (final call in calls) {
          if (call is Map) _toolCall(call, emit);
        }
      }
    }
    final finish = choice['finish_reason'];
    if (finish is String) {
      _finish = finish;
      _sawFinish = true;
      _closeCalls(emit);
    }
  }

  void _toolCall(Map<Object?, Object?> call, Emit emit) {
    final function = call['function'];
    final name = function is Map ? function['name'] : null;
    final arguments = function is Map ? function['arguments'] : null;
    final id = call['id'];
    final index = _last = _int(call['index']) ?? _guessIndex(id, name);
    if (id is String && id.isNotEmpty) _ids.putIfAbsent(index, () => id);

    var builder = _calls[index];
    if (builder == null && name is String && name.isNotEmpty) {
      _sawToolCalls = true;
      builder = _calls[index] = ToolCallBuilder(
        _ids[index] ?? 'call_$index',
        name,
      );
      _open.add(index);
      emit(builder.start());
      final early = _early.remove(index);
      if (early != null) emit(builder.add(early.toString()));
    }
    if (arguments is String && arguments.isNotEmpty) {
      if (builder == null) {
        (_early[index] ??= StringBuffer()).write(arguments);
      } else {
        emit(builder.add(arguments));
      }
    }
  }

  /// For servers that leave out `index`: a part with a new id, or a name
  /// while the last call already has one, starts the next call; anything
  /// else continues the last call.
  int _guessIndex(Object? id, Object? name) {
    final last = _last;
    if (last == null) return 0;
    final hasId = id is String && id.isNotEmpty;
    final known = _ids[last];
    final startsNew = hasId
        ? known != null && known != id
        : name is String && name.isNotEmpty && _calls[last] != null;
    return startsNew ? last + 1 : last;
  }

  void _closeCalls(Emit emit) {
    for (final index in _open) {
      emit(_calls[index]!.done());
    }
    _open.clear();
  }

  void _end(Emit emit) {
    _closeCalls(emit);
    if (_usage != null) emit(_usage!);
    emit(
      LlmDone(switch (_finish) {
        'stop' => LlmFinishReason.stop,
        'length' => LlmFinishReason.length,
        'tool_calls' || 'function_call' => LlmFinishReason.toolCalls,
        'content_filter' => LlmFinishReason.contentFilter,
        // a server that gave no reason but did call tools
        null when _sawToolCalls => LlmFinishReason.toolCalls,
        null => LlmFinishReason.stop,
        _ => LlmFinishReason.other,
      }, rawFinishReason: _finish),
    );
    _done = true;
  }

  @override
  void close(Emit emit) {
    // a server that ends the stream without `[DONE]`
    if (_sawFinish) {
      _end(emit);
    } else {
      super.close(emit);
    }
  }
}

int? _int(Object? value) => value is num ? value.toInt() : null;
