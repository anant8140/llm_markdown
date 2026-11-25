import 'dart:async';

import 'package:llm_client/llm_client.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Map<String, Object?> chunk(
  Map<String, Object?> delta, {
  String? finish,
  Map<String, Object?>? usage,
}) => {
  'id': 'chatcmpl-1',
  'object': 'chat.completion.chunk',
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
  'usage': usage,
};

Map<String, Object?> toolChunk(
  int index, {
  String? id,
  String? name,
  String? arguments,
}) => chunk({
  'tool_calls': [
    {
      'index': index,
      'id': ?id,
      if (id != null) 'type': 'function',
      'function': {'name': ?name, 'arguments': ?arguments},
    },
  ],
});

const usageChunk = {
  'choices': <Object?>[],
  'usage': {'prompt_tokens': 12, 'completion_tokens': 7, 'total_tokens': 19},
};

void main() {
  group('request', () {
    test('plain chat: URL, headers and body', () async {
      final fake = sseFake(['[DONE]']);
      await OpenAIProvider(
        apiKey: 'sk-test',
        client: fake,
      ).stream(plainRequest).drain<void>();
      final request = sentRequest(fake);
      expect(request.method, 'POST');
      expect('${request.url}', 'https://api.openai.com/v1/chat/completions');
      expect(request.headers['Authorization'], 'Bearer sk-test');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(sentBody(fake), {
        'model': 'test-model',
        'messages': [
          {'role': 'system', 'content': 'Be brief.'},
          {'role': 'user', 'content': 'Hi'},
        ],
        'stream': true,
        'stream_options': {'include_usage': true},
        'temperature': 0.5,
        'max_completion_tokens': 100,
      });
    });

    test('tools', () async {
      final fake = sseFake(['[DONE]']);
      await OpenAIProvider(
        apiKey: 'k',
        client: fake,
      ).stream(toolRequest).drain<void>();
      expect(sentBody(fake)['tools'], [
        {
          'type': 'function',
          'function': {
            'name': 'get_weather',
            'description': 'The weather in a city',
            'parameters': weatherTool.parameters,
          },
        },
      ]);
    });

    test('a compatible server: base URL, no key, max_tokens, no usage, '
        'extra fields last', () async {
      final fake = sseFake(['[DONE]']);
      final provider = OpenAIProvider(
        baseUrl: 'http://localhost:8080/v1/',
        maxTokensField: 'max_tokens',
        includeUsage: false,
        headers: {'X-Test': '1'},
        client: fake,
      );
      await provider
          .stream(
            const LlmRequest(
              model: 'local',
              messages: [LlmMessage.user('Hi')],
              temperature: 0.5,
              maxTokens: 9,
              extra: {'temperature': 1, 'seed': 3},
            ),
          )
          .drain<void>();
      final request = sentRequest(fake);
      expect('${request.url}', 'http://localhost:8080/v1/chat/completions');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers['X-Test'], '1');
      expect(sentBody(fake), {
        'model': 'local',
        'messages': [
          {'role': 'user', 'content': 'Hi'},
        ],
        'stream': true,
        'temperature': 1,
        'max_tokens': 9,
        'seed': 3,
      });
    });

    test('tool round trip', () async {
      final fake = sseFake(['[DONE]']);
      await OpenAIProvider(
        apiKey: 'k',
        client: fake,
      ).stream(roundTripRequest).drain<void>();
      expect(sentBody(fake)['messages'], [
        {'role': 'user', 'content': 'Weather in Paris and Rome?'},
        {
          'role': 'assistant',
          'content': 'Checking.',
          'tool_calls': [
            {
              'id': 'call_a',
              'type': 'function',
              'function': {
                'name': 'get_weather',
                'arguments': '{"city":"Paris"}',
              },
            },
            {
              'id': 'call_b',
              'type': 'function',
              'function': {
                'name': 'get_weather',
                'arguments': '{"city":"Rome"}',
              },
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'call_a', 'content': '{"temp": 21}'},
        {'role': 'tool', 'tool_call_id': 'call_b', 'content': 'rain'},
      ]);
    });

    test(
      'an assistant message with only tool calls has null content',
      () async {
        final fake = sseFake(['[DONE]']);
        await OpenAIProvider(apiKey: 'k', client: fake)
            .stream(
              const LlmRequest(
                model: 'm',
                messages: [
                  LlmMessage.assistant(
                    '',
                    toolCalls: [LlmToolCall(id: 'c', name: 'f')],
                  ),
                ],
              ),
            )
            .drain<void>();
        final message = (sentBody(fake)['messages'] as List).single as Map;
        expect(message.containsKey('content'), isTrue);
        expect(message['content'], isNull);
        expect(message['tool_calls'][0]['function']['arguments'], '{}');
      },
    );
  });

  group('stream', () {
    test('text, usage and finish reason', () async {
      final fake = sseFake([
        chunk({'role': 'assistant', 'content': ''}),
        chunk({'content': 'Hel'}),
        chunk({'content': 'lo'}),
        chunk({}, finish: 'stop'),
        usageChunk,
        '[DONE]',
      ]);
      expect(
        await collect(
          OpenAIProvider(apiKey: 'k', client: fake).stream(plainRequest),
        ),
        ['text:Hel', 'text:lo', 'usage:12:7', 'done:stop:stop'],
      );
    });

    test('tool calls without an index, from compatible servers', () async {
      final fake = sseFake([
        // two whole calls in one chunk, neither with an index
        chunk({
          'tool_calls': [
            {
              'id': 'a',
              'function': {'name': 'f1', 'arguments': '{"x":1}'},
            },
            {
              'id': 'b',
              'function': {'name': 'f2', 'arguments': '{"y":'},
            },
          ],
        }),
        // a later piece of the second call, with no id or name
        chunk({
          'tool_calls': [
            {
              'function': {'arguments': '2}'},
            },
          ],
        }),
        // a third call with a name but no id
        chunk({
          'tool_calls': [
            {
              'function': {'name': 'f3', 'arguments': '{}'},
            },
          ],
        }),
        chunk({}, finish: 'tool_calls'),
        '[DONE]',
      ]);
      final events = await collect(
        OpenAIProvider(apiKey: 'k', client: fake).stream(plainRequest),
      );
      expect(events.where((e) => e.startsWith('call:')), [
        'call:a:f1:{"x":1}',
        'call:b:f2:{"y":2}',
        'call:call_2:f3:{}',
      ]);
      expect(events.last, 'done:toolCalls:tool_calls');
    });

    test('thinking from compatible servers', () async {
      final fake = sseFake([
        chunk({'reasoning_content': 'Hm'}),
        chunk({'reasoning': 'm.'}),
        chunk({'content': 'Yes'}),
        chunk({}, finish: 'length'),
        '[DONE]',
      ]);
      expect(
        await collect(
          OpenAIProvider(apiKey: 'k', client: fake).stream(plainRequest),
        ),
        ['thinking:Hm', 'thinking:m.', 'text:Yes', 'done:length:length'],
      );
    });

    test('a tool call in pieces', () async {
      final fake = sseFake([
        toolChunk(0, id: 'call_1', name: 'get_weather', arguments: ''),
        toolChunk(0, arguments: '{"ci'),
        toolChunk(0, arguments: 'ty": "Par'),
        toolChunk(0, arguments: 'is"}'),
        chunk({}, finish: 'tool_calls'),
        '[DONE]',
      ]);
      expect(
        await collect(
          OpenAIProvider(apiKey: 'k', client: fake).stream(toolRequest),
        ),
        [
          'start:call_1:get_weather',
          'delta:call_1:{}:{"ci',
          'delta:call_1:{"city":"Par"}:ty": "Par',
          'delta:call_1:{"city":"Paris"}:is"}',
          'call:call_1:get_weather:{"city":"Paris"}',
          'done:toolCalls:tool_calls',
        ],
      );
    });

    test('two tool calls, mixed, and one without arguments', () async {
      final fake = sseFake([
        toolChunk(0, id: 'call_1', name: 'get_weather', arguments: '{"city":'),
        toolChunk(1, id: 'call_2', name: 'get_time'),
        toolChunk(0, arguments: '"Rome"}'),
        chunk({}, finish: 'tool_calls'),
        '[DONE]',
      ]);
      expect(
        await collect(
          OpenAIProvider(apiKey: 'k', client: fake).stream(toolRequest),
        ),
        [
          'start:call_1:get_weather',
          'delta:call_1:{}:{"city":',
          'start:call_2:get_time',
          'delta:call_1:{"city":"Rome"}:"Rome"}',
          'call:call_1:get_weather:{"city":"Rome"}',
          'call:call_2:get_time:{}',
          'done:toolCalls:tool_calls',
        ],
      );
    });

    test('earlier deltas are not changed by later ones', () async {
      final fake = sseFake([
        toolChunk(0, id: 'c', name: 'f', arguments: '{"a": [1'),
        toolChunk(0, arguments: ', 2]}'),
        chunk({}, finish: 'tool_calls'),
        '[DONE]',
      ]);
      final deltas = await OpenAIProvider(apiKey: 'k', client: fake)
          .stream(toolRequest)
          .where((event) => event is LlmToolCallDelta)
          .cast<LlmToolCallDelta>()
          .toList();
      expect(deltas[0].argumentsSoFar, {
        'a': [1],
      });
      expect(deltas[1].argumentsSoFar, {
        'a': [1, 2],
      });
    });

    test('arguments that are not JSON end with an LlmException', () async {
      final fake = sseFake([
        toolChunk(0, id: 'c', name: 'f', arguments: '{"a": nope'),
        '[DONE]',
      ]);
      await expectLater(
        OpenAIProvider(apiKey: 'k', client: fake).stream(toolRequest),
        emitsThrough(
          emitsError(
            isA<LlmException>().having((e) => e.body, 'body', '{"a": nope'),
          ),
        ),
      );
    });

    test('a server that ends without [DONE]', () async {
      final fake = sseFake([
        chunk({'content': 'Hi'}),
        chunk({}, finish: 'stop'),
      ]);
      expect(
        await collect(
          OpenAIProvider(apiKey: 'k', client: fake).stream(plainRequest),
        ),
        ['text:Hi', 'done:stop:stop'],
      );
    });

    test('a stream cut off before the end is an error', () async {
      final fake = sseFake([
        chunk({'content': 'Hi'}),
      ]);
      await expectLater(
        OpenAIProvider(apiKey: 'k', client: fake).stream(plainRequest),
        emitsInOrder([
          isA<LlmTextDelta>(),
          emitsError(isA<LlmException>()),
          emitsDone,
        ]),
      );
    });
  });

  group('errors', () {
    test('an HTTP error with a JSON body', () async {
      const body = {
        'error': {
          'message': 'Incorrect API key provided',
          'type': 'invalid_request_error',
          'code': 'invalid_api_key',
        },
      };
      final fake = errorFake(401, body);
      await expectLater(
        OpenAIProvider(apiKey: 'bad', client: fake).stream(plainRequest),
        emitsInOrder([
          emitsError(
            isA<LlmException>()
                .having((e) => e.statusCode, 'statusCode', 401)
                .having(
                  (e) => e.message,
                  'message',
                  'Incorrect API key provided',
                )
                .having((e) => e.body, 'body', contains('invalid_api_key')),
          ),
          emitsDone,
        ]),
      );
    });

    test('an HTTP error without JSON keeps the status and body', () async {
      final fake = errorFake(502, 'Bad Gateway');
      await expectLater(
        OpenAIProvider(apiKey: 'k', client: fake).stream(plainRequest),
        emitsError(
          isA<LlmException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.message, 'message', contains('502'))
              .having((e) => e.body, 'body', 'Bad Gateway'),
        ),
      );
    });

    test('an error in the middle of the stream', () async {
      final fake = sseFake([
        chunk({'content': 'Hi'}),
        {
          'error': {
            'message': 'The server had an error',
            'type': 'server_error',
          },
        },
        chunk({'content': ' never'}),
        '[DONE]',
      ]);
      await expectLater(
        OpenAIProvider(apiKey: 'k', client: fake).stream(plainRequest),
        emitsInOrder([
          isA<LlmTextDelta>(),
          emitsError(
            isA<LlmException>()
                .having((e) => e.statusCode, 'statusCode', isNull)
                .having((e) => e.message, 'message', 'The server had an error')
                .having((e) => e.body, 'body', contains('server_error')),
          ),
          emitsDone,
        ]),
      );
    });
  });

  test('cancel aborts the request', () async {
    final fake = sseFake([
      chunk({'content': 'Hi'}),
    ], keepOpen: true);
    final first = Completer<LlmEvent>();
    final subscription = OpenAIProvider(
      apiKey: 'k',
      client: fake,
    ).stream(plainRequest).listen(first.complete);
    expect(describe(await first.future), 'text:Hi');
    expect(fake.aborted, 0);
    await subscription.cancel();
    await pumpEventQueue();
    expect(fake.aborted, 1);
  });
}
