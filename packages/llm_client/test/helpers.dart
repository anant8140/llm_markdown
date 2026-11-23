import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_client/llm_client.dart';
import 'package:server_sent_events/server_sent_events.dart';
import 'package:server_sent_events/testing.dart';

/// One event as a short string, so a whole stream compares as a list.
String describe(LlmEvent event) => switch (event) {
  LlmTextDelta(:final text) => 'text:$text',
  LlmThinkingDelta(:final text) => 'thinking:$text',
  LlmToolCallStart(:final id, :final name) => 'start:$id:$name',
  LlmToolCallDelta(:final id, :final argumentsSoFar, :final rawDelta) =>
    'delta:$id:${jsonEncode(argumentsSoFar)}:$rawDelta',
  LlmToolCallDone(:final id, :final name, :final arguments) =>
    'call:$id:$name:${jsonEncode(arguments)}',
  LlmUsage(:final inputTokens, :final outputTokens) =>
    'usage:$inputTokens:$outputTokens',
  LlmDone(:final finishReason, :final rawFinishReason) =>
    'done:${finishReason.name}:$rawFinishReason',
};

/// The events of [stream], described.
Future<List<String>> collect(Stream<LlmEvent> stream) =>
    stream.map(describe).toList();

/// A fake client answering every request with the SSE [events]: JSON
/// objects, or strings sent as they are. [types] names the SSE event type
/// of each JSON object from its `type` field, as Anthropic does.
FakeSseClient sseFake(
  List<Object> events, {
  bool keepOpen = false,
  bool types = false,
}) => FakeSseClient(
  (_) => FakeSseResponse.events([
    for (final event in events)
      event is String
          ? SseEvent(event)
          : SseEvent(
              jsonEncode(event),
              event: types ? '${(event as Map)['type']}' : 'message',
            ),
  ], keepOpen: keepOpen),
);

/// A fake client answering with an HTTP error.
FakeSseClient errorFake(int status, Object body) => FakeSseClient(
  (_) =>
      FakeSseResponse.error(status, body is String ? body : jsonEncode(body)),
);

/// The JSON body of the only request [fake] got.
Map<String, Object?> sentBody(FakeSseClient fake) =>
    jsonDecode(fake.bodies.single) as Map<String, Object?>;

/// The only request [fake] got.
http.BaseRequest sentRequest(FakeSseClient fake) => fake.requests.single;

const weatherTool = LlmTool(
  name: 'get_weather',
  description: 'The weather in a city',
  parameters: {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
    },
    'required': ['city'],
  },
);

/// A plain chat with a system message and settings.
const plainRequest = LlmRequest(
  model: 'test-model',
  messages: [LlmMessage.system('Be brief.'), LlmMessage.user('Hi')],
  temperature: 0.5,
  maxTokens: 100,
);

/// A chat with a tool to call.
const toolRequest = LlmRequest(
  model: 'test-model',
  messages: [LlmMessage.user('Weather in Paris?')],
  tools: [weatherTool],
);

/// The second request of a tool round trip: the assistant's calls and
/// their results.
const roundTripRequest = LlmRequest(
  model: 'test-model',
  messages: [
    LlmMessage.user('Weather in Paris and Rome?'),
    LlmMessage.assistant(
      'Checking.',
      toolCalls: [
        LlmToolCall(
          id: 'call_a',
          name: 'get_weather',
          arguments: {'city': 'Paris'},
        ),
        LlmToolCall(
          id: 'call_b',
          name: 'get_weather',
          arguments: {'city': 'Rome'},
        ),
      ],
    ),
    LlmMessage.tool(toolCallId: 'call_a', text: '{"temp": 21}'),
    LlmMessage.tool(toolCallId: 'call_b', text: 'rain'),
  ],
  tools: [weatherTool],
);
