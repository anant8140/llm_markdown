# llm_client

One API for streaming chat with OpenAI, Anthropic, Gemini and Ollama.

- **One request, one stream of events** for every provider: text,
  thinking, tool calls, usage and the finish reason, as a sealed class you
  can `switch` over.
- **Tool arguments while they are written:** each piece gives the
  arguments so far as a `Map`, read from the unfinished JSON.
- **Errors you can show:** a failed request, or an error in the middle of
  a stream, is one `LlmException` with the status, the provider's message
  and the raw body.
- **Cancel closes the request:** cancelling the subscription aborts the
  HTTP request, so a stop button stops the reply.
- **Pure Dart:** no Flutter and no `dart:io` in the library. It depends
  on `http`, [server_sent_events] and [partial_json].

It covers streaming chat with text and tools. It does not cover images,
audio, files, embeddings, or non-streaming requests.

[server_sent_events]: https://pub.dev/packages/server_sent_events
[partial_json]: https://pub.dev/packages/partial_json

## Usage

```dart
import 'package:llm_client/llm_client.dart';

final provider = OpenAIProvider(apiKey: apiKey);

const request = LlmRequest(
  model: 'gpt-4.1-mini',
  messages: [
    LlmMessage.system('Answer briefly.'),
    LlmMessage.user('Why is the sky blue?'),
  ],
  temperature: 0.7,
  maxTokens: 500,
);

// the text only
await for (final text in provider.text(request)) {
  stdout.write(text);
}

// every event
await for (final event in provider.stream(request)) {
  switch (event) {
    case LlmTextDelta(:final text): stdout.write(text);
    case LlmThinkingDelta(:final text): stderr.write(text);
    case LlmToolCallStart(:final name): print('calling $name');
    case LlmToolCallDelta(:final argumentsSoFar): print(argumentsSoFar);
    case LlmToolCallDone(:final toolCall): print(toolCall);
    case LlmUsage(:final inputTokens, :final outputTokens):
      print('$inputTokens in, $outputTokens out');
    case LlmDone(:final finishReason): print(finishReason);
  }
}

// the whole reply at once
final reply = await provider.complete(request);
print(reply.text);
```

A complete reply ends with `LlmUsage`, when the provider reports usage,
and then `LlmDone`. The HTTP request starts when the stream is listened
to.

## Providers

The request is the same for all of them; only the model name changes.

```dart
// OpenAI Chat Completions
final openai = OpenAIProvider(apiKey: apiKey);

// A server that speaks the OpenAI format: Groq, OpenRouter, vLLM, LM Studio ...
final local = OpenAIProvider(
  baseUrl: 'http://localhost:1234/v1',
  maxTokensField: 'max_tokens', // for servers without max_completion_tokens
);

// Anthropic Messages
final anthropic = AnthropicProvider(apiKey: apiKey, version: '2023-06-01');

// Gemini
final gemini = GeminiProvider(apiKey: apiKey);

// Ollama's own API
final ollama = OllamaProvider(baseUrl: 'http://localhost:11434');
```

Each takes `headers` for extra request headers and `client` to reuse an
`http.Client` (which the provider does not close). Without `client`, a
client is made for each request and closed with it.

| | sent to | system messages | `maxTokens` |
| --- | --- | --- | --- |
| `OpenAIProvider` | `<baseUrl>/chat/completions` | messages | `max_completion_tokens` |
| `AnthropicProvider` | `<baseUrl>/messages` | top-level `system` | `max_tokens` (4096 when null: the API needs it) |
| `GeminiProvider` | `<baseUrl>/models/<model>:streamGenerateContent?alt=sse` | `systemInstruction` | `generationConfig.maxOutputTokens` |
| `OllamaProvider` | `<baseUrl>/api/chat` | messages | `options.num_predict` |

### What only one provider has

`LlmRequest.extra` is added to the top level of the request body after
everything else, so it can also replace a field:

```dart
LlmRequest(
  model: 'claude-sonnet-4-5',
  messages: messages,
  maxTokens: 4000,
  extra: {
    'thinking': {'type': 'enabled', 'budget_tokens': 2000},
  },
);
```

Thinking arrives as `LlmThinkingDelta` from Anthropic (`thinking_delta`),
Gemini (parts with `thought: true`; ask for them with
`extra: {'generationConfig': ...}`, which replaces the whole
`generationConfig`), Ollama (`message.thinking`, with `extra: {'think':
true}`) and from OpenAI-compatible servers that send `reasoning_content`
or `reasoning`. OpenAI's own Chat Completions API does not send it.

## Tools

```dart
const weather = LlmTool(
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

final messages = [const LlmMessage.user('What is the weather in Paris?')];

final reply = await provider.complete(
  LlmRequest(model: model, messages: messages, tools: const [weather]),
);

if (reply.finishReason == LlmFinishReason.toolCalls) {
  messages.add(reply.message); // the assistant message with its calls
  for (final call in reply.toolCalls) {
    final result = await getWeather(call.arguments['city'] as String);
    messages.add(LlmMessage.tool(toolCallId: call.id, text: result));
  }
  final answer = await provider.complete(
    LlmRequest(model: model, messages: messages, tools: const [weather]),
  );
  print(answer.text);
}
```

While streaming, a call is `LlmToolCallStart`, then `LlmToolCallDelta`s
whose `argumentsSoFar` grows (`{}`, `{city: Par}`, `{city: Paris}`), then
`LlmToolCallDone` with the complete arguments. OpenAI and Anthropic send
the arguments in pieces. Gemini and Ollama send each call whole, so there
is one delta with all of it.

Gemini and older Ollama versions give calls no ID; they get `call_0`,
`call_1` and so on. Gemini and Ollama name the tool in a result: the name
is taken from the assistant message that made the call, or from
`LlmMessage.tool(toolName: ...)`. For Gemini a result that is a JSON
object is sent as it is, and any other text as `{"result": text}`.

Keep the `LlmToolCall` objects you got and send them back unchanged:
`providerData` holds what a provider wants returned with a call (Gemini's
call ID and `thoughtSignature`).

## Errors

```dart
try {
  await for (final text in provider.text(request)) {
    stdout.write(text);
  }
} on LlmException catch (error) {
  print(error.statusCode); // 401, or null for an error inside the stream
  print(error.message);    // Incorrect API key provided
  print(error.body);       // the raw JSON the API sent
}
```

An `LlmException` is thrown for:

- a status that is not 2xx; `message` is the provider's message when the
  body is JSON that has one, otherwise `HTTP <status> from <url>`;
- an error event in the middle of a stream;
- a prompt Gemini blocked (`promptFeedback.blockReason`);
- a reply that cannot be read: a chunk that is not JSON, or tool
  arguments that are not a JSON object;
- a connection that closes before the reply is finished (no finish
  reason, `message_stop` or `done: true` was received).

Network errors, such as no connection, come through as `package:http`
throws them (`ClientException`). Nothing is retried.

## Cancel

```dart
final subscription = provider.stream(request).listen(onEvent);
// later, from a stop button:
await subscription.cancel(); // aborts the HTTP request
```

Leaving an `await for` loop with `break` cancels too.

## Testing

Tests need no network. `FakeSseClient` from
`package:server_sent_events/testing.dart` is an `http.Client` that answers
with events you give it:

```dart
import 'package:server_sent_events/server_sent_events.dart';
import 'package:server_sent_events/testing.dart';

final fake = FakeSseClient((request) => FakeSseResponse.events([
  const SseEvent('{"choices":[{"delta":{"content":"Hi"},"finish_reason":"stop"}]}'),
  const SseEvent('[DONE]'),
]));
final provider = OpenAIProvider(apiKey: 'test', client: fake);

expect(await provider.text(request).join(), 'Hi');
expect(fake.bodies.single, contains('"model"'));

// an API error
FakeSseClient((_) => FakeSseResponse.error(401, '{"error":{"message":"Bad key"}}'));
```

For Ollama, give the lines with `FakeSseResponse.raw(['{...}\n', ...])`.
To test your own code without any wire format, extend `LlmProvider` and
return the events you want from `stream`.

## What has been checked against a real server

**Ollama 0.40** with a local model (`qwen3.6:27b`), through Ollama's own
API with `OllamaProvider` and through its OpenAI-compatible endpoint with
`OpenAIProvider(baseUrl: 'http://localhost:11434/v1')`:

- text in several deltas, the finish reason and token usage;
- thinking deltas, kept apart from the text;
- a tool call (start, delta, done, arguments as a map), and the round trip
  with the tool's result, including `tool_name` and the call's `id`;
- cancelling in the middle, after which the server answers again at once;
- an unknown model as an `LlmException` with status 404, and a server that
  is not there as an error.

`dart run tool/live_ollama.dart [--openai] [model]` runs these checks.

The OpenAI wire format is therefore checked against one real server, with
`max_completion_tokens`, `stream_options` and streamed tool calls. OpenAI's
own API, Anthropic and Gemini have not been called yet: those providers
were written from the published wire formats and are tested against fake
responses built from them. In particular, these have not been checked
live:

- **OpenAI:** `max_completion_tokens` and `stream_options` on compatible
  servers (both can be changed or turned off); the `reasoning_content` /
  `reasoning` fields, which differ between servers.
- **Anthropic:** extended thinking together with tools. The API wants the
  thinking blocks, with their signatures, sent back in the assistant
  message of a tool round trip; `LlmMessage` does not carry them, so that
  combination is not expected to work yet.
- **Gemini:** the `id` and `thoughtSignature` of function calls on Gemini
  3 models, and that sending them back as `providerData` satisfies the
  API. Signatures on parts that are not function calls are dropped.
  `outputTokens` adds `thoughtsTokenCount` to `candidatesTokenCount`.
- **Ollama:** versions before 0.40, which may not send `message.thinking`
  or tool-call ids.
- **Finish reasons:** Gemini and Ollama report a plain stop when the model
  called tools; this package reports `toolCalls` when the reply had any.
  Reasons without a matching name are `LlmFinishReason.other`, with the
  provider's own word in `rawFinishReason`.
- **The web:** cancelling and streaming rely on `package:http`'s browser
  client; only the Dart VM was tested.

Only the first candidate or choice of a reply is read. Cache token counts
and other usage details are not reported.

## License

MIT
