import 'dart:async';

import 'package:llm_client/llm_client.dart';
import 'package:server_sent_events/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const messageStart = {
  'type': 'message_start',
  'message': {
    'id': 'msg_1',
    'role': 'assistant',
    'content': <Object?>[],
    'usage': {'input_tokens': 25, 'output_tokens': 1},
  },
};

Map<String, Object?> blockStart(int index, Map<String, Object?> block) => {
  'type': 'content_block_start',
  'index': index,
  'content_block': block,
};

Map<String, Object?> blockDelta(int index, Map<String, Object?> delta) => {
  'type': 'content_block_delta',
  'index': index,
  'delta': delta,
};

Map<String, Object?> blockStop(int index) => {
  'type': 'content_block_stop',
  'index': index,
};

Map<String, Object?> messageDelta(String stop, int outputTokens) => {
  'type': 'message_delta',
  'delta': {'stop_reason': stop, 'stop_sequence': null},
  'usage': {'output_tokens': outputTokens},
};

const messageStop = {'type': 'message_stop'};
const ping = {'type': 'ping'};

AnthropicProvider provider(FakeSseClient fake) =>
    AnthropicProvider(apiKey: 'sk-ant-test', client: fake);

void main() {
  group('request', () {
    test('plain chat: URL, headers and body', () async {
      final fake = sseFake([messageStop], types: true);
      await provider(fake).stream(plainRequest).drain<void>();
      final request = sentRequest(fake);
      expect(request.method, 'POST');
      expect('${request.url}', 'https://api.anthropic.com/v1/messages');
      expect(request.headers['x-api-key'], 'sk-ant-test');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(sentBody(fake), {
        'model': 'test-model',
        'max_tokens': 100,
        'system': 'Be brief.',
        'messages': [
          {'role': 'user', 'content': 'Hi'},
        ],
        'stream': true,
        'temperature': 0.5,
      });
    });

    test('version, default max_tokens, no system, extra fields last', () async {
      final fake = sseFake([messageStop], types: true);
      await AnthropicProvider(
            apiKey: 'k',
            version: '2099-01-01',
            defaultMaxTokens: 512,
            client: fake,
          )
          .stream(
            const LlmRequest(
              model: 'm',
              messages: [LlmMessage.user('Hi')],
              extra: {
                'thinking': {'type': 'enabled', 'budget_tokens': 1024},
                'stream': true,
              },
            ),
          )
          .drain<void>();
      expect(sentRequest(fake).headers['anthropic-version'], '2099-01-01');
      expect(sentBody(fake), {
        'model': 'm',
        'max_tokens': 512,
        'messages': [
          {'role': 'user', 'content': 'Hi'},
        ],
        'stream': true,
        'thinking': {'type': 'enabled', 'budget_tokens': 1024},
      });
    });

    test('tools', () async {
      final fake = sseFake([messageStop], types: true);
      await provider(fake).stream(toolRequest).drain<void>();
      expect(sentBody(fake)['tools'], [
        {
          'name': 'get_weather',
          'description': 'The weather in a city',
          'input_schema': weatherTool.parameters,
        },
      ]);
    });

    test('tool round trip', () async {
      final fake = sseFake([messageStop], types: true);
      await provider(fake).stream(roundTripRequest).drain<void>();
      expect(sentBody(fake)['messages'], [
        {'role': 'user', 'content': 'Weather in Paris and Rome?'},
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'Checking.'},
            {
              'type': 'tool_use',
              'id': 'call_a',
              'name': 'get_weather',
              'input': {'city': 'Paris'},
            },
            {
              'type': 'tool_use',
              'id': 'call_b',
              'name': 'get_weather',
              'input': {'city': 'Rome'},
            },
          ],
        },
        // both results in one user message
        {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'call_a',
              'content': '{"temp": 21}',
            },
            {'type': 'tool_result', 'tool_use_id': 'call_b', 'content': 'rain'},
          ],
        },
      ]);
    });

    test('a user message after tool results stays its own message', () async {
      final fake = sseFake([messageStop], types: true);
      await provider(fake)
          .stream(
            const LlmRequest(
              model: 'm',
              messages: [
                LlmMessage.assistant(
                  '',
                  toolCalls: [LlmToolCall(id: 'c', name: 'f')],
                ),
                LlmMessage.tool(toolCallId: 'c', text: 'ok'),
                LlmMessage.user('Thanks'),
              ],
            ),
          )
          .drain<void>();
      expect(sentBody(fake)['messages'], [
        {
          'role': 'assistant',
          'content': [
            {'type': 'tool_use', 'id': 'c', 'name': 'f', 'input': {}},
          ],
        },
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'c', 'content': 'ok'},
          ],
        },
        {'role': 'user', 'content': 'Thanks'},
      ]);
    });
  });

  group('stream', () {
    test('text, usage and finish reason', () async {
      final fake = sseFake([
        messageStart,
        blockStart(0, {'type': 'text', 'text': ''}),
        ping,
        blockDelta(0, {'type': 'text_delta', 'text': 'Hel'}),
        blockDelta(0, {'type': 'text_delta', 'text': 'lo'}),
        blockStop(0),
        messageDelta('end_turn', 9),
        messageStop,
      ], types: true);
      expect(await collect(provider(fake).stream(plainRequest)), [
        'text:Hel',
        'text:lo',
        'usage:25:9',
        'done:stop:end_turn',
      ]);
    });

    test('thinking, then text, cut off by max_tokens', () async {
      final fake = sseFake([
        messageStart,
        blockStart(0, {'type': 'thinking', 'thinking': ''}),
        blockDelta(0, {'type': 'thinking_delta', 'thinking': 'Let me '}),
        blockDelta(0, {'type': 'thinking_delta', 'thinking': 'see.'}),
        blockDelta(0, {'type': 'signature_delta', 'signature': 'EqQB'}),
        blockStop(0),
        blockStart(1, {'type': 'text', 'text': ''}),
        blockDelta(1, {'type': 'text_delta', 'text': '42'}),
        blockStop(1),
        messageDelta('max_tokens', 30),
        messageStop,
      ], types: true);
      expect(await collect(provider(fake).stream(plainRequest)), [
        'thinking:Let me ',
        'thinking:see.',
        'text:42',
        'usage:25:30',
        'done:length:max_tokens',
      ]);
    });

    test('a tool call in pieces, after text', () async {
      final fake = sseFake([
        messageStart,
        blockStart(0, {'type': 'text', 'text': ''}),
        blockDelta(0, {'type': 'text_delta', 'text': 'Checking.'}),
        blockStop(0),
        blockStart(1, {
          'type': 'tool_use',
          'id': 'toolu_1',
          'name': 'get_weather',
          'input': <String, Object?>{},
        }),
        blockDelta(1, {'type': 'input_json_delta', 'partial_json': ''}),
        blockDelta(1, {'type': 'input_json_delta', 'partial_json': '{"city"'}),
        blockDelta(1, {'type': 'input_json_delta', 'partial_json': ': "Pa'}),
        blockDelta(1, {'type': 'input_json_delta', 'partial_json': 'ris"}'}),
        blockStop(1),
        messageDelta('tool_use', 20),
        messageStop,
      ], types: true);
      expect(await collect(provider(fake).stream(toolRequest)), [
        'text:Checking.',
        'start:toolu_1:get_weather',
        'delta:toolu_1:{}:{"city"',
        'delta:toolu_1:{"city":"Pa"}:: "Pa',
        'delta:toolu_1:{"city":"Paris"}:ris"}',
        'call:toolu_1:get_weather:{"city":"Paris"}',
        'usage:25:20',
        'done:toolCalls:tool_use',
      ]);
    });

    test('two tool calls, the second without arguments', () async {
      final fake = sseFake([
        messageStart,
        blockStart(0, {
          'type': 'tool_use',
          'id': 't1',
          'name': 'a',
          'input': {},
        }),
        blockDelta(0, {'type': 'input_json_delta', 'partial_json': '{"x":1}'}),
        blockStop(0),
        blockStart(1, {
          'type': 'tool_use',
          'id': 't2',
          'name': 'b',
          'input': {},
        }),
        blockStop(1),
        messageDelta('tool_use', 5),
        messageStop,
      ], types: true);
      expect(await collect(provider(fake).stream(toolRequest)), [
        'start:t1:a',
        'delta:t1:{"x":1}:{"x":1}',
        'call:t1:a:{"x":1}',
        'start:t2:b',
        'call:t2:b:{}',
        'usage:25:5',
        'done:toolCalls:tool_use',
      ]);
    });

    test('a stream cut off before message_stop is an error', () async {
      final fake = sseFake([
        messageStart,
        blockDelta(0, {'type': 'text_delta', 'text': 'Hi'}),
      ], types: true);
      await expectLater(
        provider(fake).stream(plainRequest),
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
      final fake = errorFake(401, {
        'type': 'error',
        'error': {
          'type': 'authentication_error',
          'message': 'invalid x-api-key',
        },
      });
      await expectLater(
        provider(fake).stream(plainRequest),
        emitsInOrder([
          emitsError(
            isA<LlmException>()
                .having((e) => e.statusCode, 'statusCode', 401)
                .having((e) => e.message, 'message', 'invalid x-api-key')
                .having(
                  (e) => e.body,
                  'body',
                  contains('authentication_error'),
                ),
          ),
          emitsDone,
        ]),
      );
    });

    test('an error event in the middle of the stream', () async {
      final fake = sseFake([
        messageStart,
        blockDelta(0, {'type': 'text_delta', 'text': 'Hi'}),
        {
          'type': 'error',
          'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
        },
        blockDelta(0, {'type': 'text_delta', 'text': ' never'}),
        messageStop,
      ], types: true);
      await expectLater(
        provider(fake).stream(plainRequest),
        emitsInOrder([
          isA<LlmTextDelta>(),
          emitsError(
            isA<LlmException>()
                .having((e) => e.statusCode, 'statusCode', isNull)
                .having((e) => e.message, 'message', 'Overloaded')
                .having((e) => e.body, 'body', contains('overloaded_error')),
          ),
          emitsDone,
        ]),
      );
    });
  });

  test('cancel aborts the request', () async {
    final fake = sseFake(
      [
        messageStart,
        blockDelta(0, {'type': 'text_delta', 'text': 'Hi'}),
      ],
      keepOpen: true,
      types: true,
    );
    final first = Completer<LlmEvent>();
    final subscription = provider(
      fake,
    ).stream(plainRequest).listen(first.complete);
    expect(describe(await first.future), 'text:Hi');
    expect(fake.aborted, 0);
    await subscription.cancel();
    await pumpEventQueue();
    expect(fake.aborted, 1);
  });
}
