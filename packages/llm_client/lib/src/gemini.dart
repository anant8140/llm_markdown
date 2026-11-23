import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:server_sent_events/server_sent_events.dart';

import 'provider.dart';
import 'streaming.dart';
import 'types.dart';

/// Google's Gemini API (`streamGenerateContent`).
class GeminiProvider extends LlmProvider {
  /// A provider using [apiKey], sent as the `x-goog-api-key` header.
  ///
  /// [headers] are added to every request. Give [client] to reuse an
  /// [http.Client]; it is not closed by this class.
  GeminiProvider({
    required this.apiKey,
    String baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    this.headers = const {},
    http.Client? client,
  }) : baseUrl = Uri.parse(baseUrl),
       _client = client;

  /// The API key.
  final String apiKey;

  /// The address of the API, up to and including the version (`/v1beta`).
  final Uri baseUrl;

  /// Extra headers for every request.
  final Map<String, String> headers;

  final http.Client? _client;

  @override
  Stream<LlmEvent> stream(LlmRequest request) => sseStream(
    url: urlFor(request.model),
    headers: {'x-goog-api-key': apiKey, ...headers},
    body: buildBody(request),
    client: _client,
    decoder: _GeminiDecoder.new,
  );

  /// The address a request to [model] is sent to. A name without a `/` is
  /// a model (`models/<name>`); one with a `/`, such as
  /// `tunedModels/abc`, is used as it is.
  Uri urlFor(String model) {
    final base = baseUrl.toString();
    return Uri.parse(
      '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}'
      '/${model.contains('/') ? model : 'models/$model'}'
      ':streamGenerateContent?alt=sse',
    );
  }

  /// The JSON body sent for [request]. The model is in the URL.
  Map<String, Object?> buildBody(LlmRequest request) {
    final system = [
      for (final message in request.messages)
        if (message.role == LlmRole.system && message.text.isNotEmpty)
          {'text': message.text},
    ];
    final contents = <Map<String, Object?>>[];
    for (final message in request.messages) {
      switch (message.role) {
        case LlmRole.system:
          break;
        case LlmRole.user:
          contents.add({
            'role': 'user',
            'parts': [
              {'text': message.text},
            ],
          });
        case LlmRole.assistant:
          contents.add({
            'role': 'model',
            'parts': [
              if (message.text.isNotEmpty || message.toolCalls.isEmpty)
                {'text': message.text},
              for (final call in message.toolCalls)
                {
                  'functionCall': {
                    if (call.providerData['id'] != null)
                      'id': call.providerData['id'],
                    'name': call.name,
                    'args': call.arguments,
                  },
                  if (call.providerData['thoughtSignature'] != null)
                    'thoughtSignature': call.providerData['thoughtSignature'],
                },
            ],
          });
        case LlmRole.tool:
          final call = callFor(message, request.messages);
          final part = {
            'functionResponse': {
              if (call?.providerData['id'] != null)
                'id': call!.providerData['id'],
              'name': toolNameFor(message, request.messages),
              'response': _response(message.text),
            },
          };
          // the results of one turn go in one user content
          final last = contents.isEmpty ? null : contents.last;
          final parts = last?['parts'];
          if (last != null &&
              last['role'] == 'user' &&
              parts is List &&
              parts.every((p) => p is Map && p['functionResponse'] != null)) {
            parts.add(part);
          } else {
            contents.add({
              'role': 'user',
              'parts': <Object?>[part],
            });
          }
      }
    }
    final config = {
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.maxTokens != null) 'maxOutputTokens': request.maxTokens,
    };
    return {
      if (system.isNotEmpty) 'systemInstruction': {'parts': system},
      'contents': contents,
      if (request.tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final tool in request.tools)
                {
                  'name': tool.name,
                  if (tool.description.isNotEmpty)
                    'description': tool.description,
                  'parameters': tool.parameters,
                },
            ],
          },
        ],
      if (config.isNotEmpty) 'generationConfig': config,
      ...request.extra,
    };
  }

  // A function response is a JSON object: a result that is one is sent as
  // it is, anything else as `{"result": text}`.
  Map<String, Object?> _response(String text) {
    try {
      final json = jsonDecode(text);
      if (json is Map<String, Object?>) return json;
    } on FormatException {
      // plain text
    }
    return {'result': text};
  }
}

class _GeminiDecoder extends WireDecoder<SseEvent> {
  LlmUsage? _usage;
  var _calls = 0;
  var _done = false;

  @override
  bool get isDone => _done;

  @override
  void add(SseEvent event, Emit emit) {
    if (event.data.trim().isEmpty) return;
    final json = decodeObject(event.data);
    throwIfError(json, event.data);

    final usage = json['usageMetadata'];
    if (usage is Map) {
      final output = _int(usage['candidatesTokenCount']);
      final thoughts = _int(usage['thoughtsTokenCount']);
      _usage = LlmUsage(
        inputTokens: _int(usage['promptTokenCount']),
        outputTokens: output == null && thoughts == null
            ? null
            : (output ?? 0) + (thoughts ?? 0),
      );
    }
    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      final feedback = json['promptFeedback'];
      final reason = feedback is Map ? feedback['blockReason'] : null;
      if (reason != null) {
        throw LlmException('The prompt was blocked: $reason', body: event.data);
      }
      return;
    }
    final candidate = candidates.first;
    if (candidate is! Map) return;
    final content = candidate['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is List) {
      for (final part in parts) {
        if (part is Map) _part(part, emit);
      }
    }
    final finish = candidate['finishReason'];
    if (finish is String) {
      if (_usage != null) emit(_usage!);
      emit(
        LlmDone(switch (finish) {
          // a reply that calls functions also ends with STOP
          'STOP' when _calls > 0 => LlmFinishReason.toolCalls,
          'STOP' => LlmFinishReason.stop,
          'MAX_TOKENS' => LlmFinishReason.length,
          'SAFETY' ||
          'RECITATION' ||
          'BLOCKLIST' ||
          'PROHIBITED_CONTENT' ||
          'SPII' ||
          'IMAGE_SAFETY' => LlmFinishReason.contentFilter,
          _ => LlmFinishReason.other,
        }, rawFinishReason: finish),
      );
      _done = true;
    }
  }

  void _part(Map<Object?, Object?> part, Emit emit) {
    final call = part['functionCall'];
    if (call is Map) {
      // function calls arrive whole, and before Gemini 3 without an ID
      final id = call['id'];
      final signature = part['thoughtSignature'];
      emitWholeToolCall(
        emit,
        id: id is String && id.isNotEmpty ? id : 'call_$_calls',
        name: '${call['name'] ?? ''}',
        arguments: call['args'],
        providerData: {
          if (id is String && id.isNotEmpty) 'id': id,
          'thoughtSignature': ?signature,
        },
      );
      _calls++;
      return;
    }
    final text = part['text'];
    if (text is! String || text.isEmpty) return;
    emit(part['thought'] == true ? LlmThinkingDelta(text) : LlmTextDelta(text));
  }
}

int? _int(Object? value) => value is num ? value.toInt() : null;
