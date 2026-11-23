import 'dart:async';

import 'package:llm_client/llm_client.dart';
import 'package:server_sent_events/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Map<String, Object?> candidate(
  List<Map<String, Object?>> parts, {
  String? finish,
  Map<String, Object?>? usage,
}) => {
  'candidates': [
    {
      'content': {'role': 'model', 'parts': parts},
      'finishReason': ?finish,
      'index': 0,
    },
  ],
  'usageMetadata': ?usage,
};

final stop = candidate([], finish: 'STOP');

GeminiProvider provider(FakeSseClient fake) =>
    GeminiProvider(apiKey: 'g-key', client: fake);

void main() {
  group('request', () {
    test('plain chat: URL, headers and body', () async {
      final fake = sseFake([stop]);
      await provider(fake).stream(plainRequest).drain<void>();
      final request = sentRequest(fake);
      expect(request.method, 'POST');
      expect(
        '${request.url}',
        'https://generativelanguage.googleapis.com/v1beta/models/test-model'
            ':streamGenerateContent?alt=sse',
      );
      expect(request.headers['x-goog-api-key'], 'g-key');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(sentBody(fake), {
        'systemInstruction': {
          'parts': [
            {'text': 'Be brief.'},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': 'Hi'},
            ],
          },
        ],
        'generationConfig': {'temperature': 0.5, 'maxOutputTokens': 100},
      });
    });

    test('no settings, a tuned model name, extra fields last', () async {
      final fake = sseFake([stop]);
      await provider(fake)
          .stream(
            const LlmRequest(
              model: 'tunedModels/mine',
              messages: [LlmMessage.user('Hi')],
              extra: {'safetySettings': <Object?>[]},
            ),
          )
          .drain<void>();
      expect(
        sentRequest(fake).url.path,
        '/v1beta/tunedModels/mine:streamGenerateContent',
      );
      expect(sentBody(fake), {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': 'Hi'},
            ],
          },
        ],
        'safetySettings': <Object?>[],
      });
    });

    test('tools', () async {
      final fake = sseFake([stop]);
      await provider(fake).stream(toolRequest).drain<void>();
      expect(sentBody(fake)['tools'], [
        {
          'functionDeclarations': [
            {
              'name': 'get_weather',
              'description': 'The weather in a city',
              'parameters': weatherTool.parameters,
            },
          ],
        },
      ]);
    });

    test('tool round trip', () async {
      final fake = sseFake([stop]);
      await provider(fake).stream(roundTripRequest).drain<void>();
      expect(sentBody(fake)['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'Weather in Paris and Rome?'},
          ],
        },
        {
          'role': 'model',
          'parts': [
            {'text': 'Checking.'},
            {
              'functionCall': {
                'name': 'get_weather',
                'args': {'city': 'Paris'},
              },
            },
            {
              'functionCall': {
                'name': 'get_weather',
                'args': {'city': 'Rome'},
              },
            },
          ],
        },
        // both results in one user content; the name comes from the call,
        // a JSON object result is sent as it is, text as {"result": ...}
        {
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': 'get_weather',
                'response': {'temp': 21},
              },
            },
            {
              'functionResponse': {
                'name': 'get_weather',
                'response': {'result': 'rain'},
              },
            },
          ],
        },
      ]);
    });

    test(
      'a call ID and thought signature from the API are sent back',
      () async {
        final first = sseFake([
          candidate([
            {
              'functionCall': {
                'id': 'fc_9',
                'name': 'get_weather',
                'args': {'city': 'Oslo'},
              },
              'thoughtSignature': 'c2ln',
            },
          ], finish: 'STOP'),
        ]);
        final reply = await provider(first).complete(toolRequest);
        expect(reply.toolCalls.single.id, 'fc_9');

        final second = sseFake([stop]);
        await provider(second)
            .stream(
              LlmRequest(
                model: 'm',
                messages: [
                  reply.message,
                  const LlmMessage.tool(
                    toolCallId: 'fc_9',
                    text: 'snow',
                    toolName: 'weather_named_here',
                  ),
                ],
              ),
            )
            .drain<void>();
        expect(sentBody(second)['contents'], [
          {
            'role': 'model',
            'parts': [
              {
                'functionCall': {
                  'id': 'fc_9',
                  'name': 'get_weather',
                  'args': {'city': 'Oslo'},
                },
                'thoughtSignature': 'c2ln',
              },
            ],
          },
          {
            'role': 'user',
            'parts': [
              {
                'functionResponse': {
                  'id': 'fc_9',
                  'name': 'weather_named_here',
                  'response': {'result': 'snow'},
                },
              },
            ],
          },
        ]);
      },
    );
  });

  group('stream', () {
    test('text, usage and finish reason', () async {
      final fake = sseFake([
        candidate(
          [
            {'text': 'Hel'},
          ],
          usage: {'promptTokenCount': 8, 'candidatesTokenCount': 1},
        ),
        candidate(
          [
            {'text': 'lo'},
          ],
          finish: 'STOP',
          usage: {
            'promptTokenCount': 8,
            'candidatesTokenCount': 4,
            'totalTokenCount': 12,
          },
        ),
      ]);
      expect(await collect(provider(fake).stream(plainRequest)), [
        'text:Hel',
        'text:lo',
        'usage:8:4',
        'done:stop:STOP',
      ]);
    });

    test('thinking parts; thinking tokens count as output', () async {
      final fake = sseFake([
        candidate([
          {'text': 'Let me see.', 'thought': true},
        ]),
        candidate(
          [
            {'text': '42'},
          ],
          finish: 'MAX_TOKENS',
          usage: {
            'promptTokenCount': 8,
            'candidatesTokenCount': 2,
            'thoughtsTokenCount': 30,
          },
        ),
      ]);
      expect(await collect(provider(fake).stream(plainRequest)), [
        'thinking:Let me see.',
        'text:42',
        'usage:8:32',
        'done:length:MAX_TOKENS',
      ]);
    });

    test('tool calls arrive whole, in several chunks', () async {
      final fake = sseFake([
        candidate([
          {'text': 'Checking.'},
          {
            'functionCall': {
              'name': 'get_weather',
              'args': {'city': 'Paris'},
            },
          },
        ]),
        candidate([
          {
            'functionCall': {'name': 'get_time'},
          },
        ], finish: 'STOP'),
      ]);
      expect(await collect(provider(fake).stream(toolRequest)), [
        'text:Checking.',
        'start:call_0:get_weather',
        'delta:call_0:{"city":"Paris"}:{"city":"Paris"}',
        'call:call_0:get_weather:{"city":"Paris"}',
        'start:call_1:get_time',
        'delta:call_1:{}:{}',
        'call:call_1:get_time:{}',
        'done:toolCalls:STOP',
      ]);
    });

    test('a reply stopped by the safety filter', () async {
      final fake = sseFake([candidate([], finish: 'SAFETY')]);
      expect(await collect(provider(fake).stream(plainRequest)), [
        'done:contentFilter:SAFETY',
      ]);
    });

    test('a stream cut off before a finish reason is an error', () async {
      final fake = sseFake([
        candidate([
          {'text': 'Hi'},
        ]),
      ]);
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
      final fake = errorFake(400, {
        'error': {
          'code': 400,
          'message': 'API key not valid. Please pass a valid API key.',
          'status': 'INVALID_ARGUMENT',
        },
      });
      await expectLater(
        provider(fake).stream(plainRequest),
        emitsInOrder([
          emitsError(
            isA<LlmException>()
                .having((e) => e.statusCode, 'statusCode', 400)
                .having(
                  (e) => e.message,
                  'message',
                  'API key not valid. Please pass a valid API key.',
                )
                .having((e) => e.body, 'body', contains('INVALID_ARGUMENT')),
          ),
          emitsDone,
        ]),
      );
    });

    test('an HTTP error whose body is a list', () async {
      final fake = errorFake(429, [
        {
          'error': {'code': 429, 'message': 'Quota exceeded'},
        },
      ]);
      await expectLater(
        provider(fake).stream(plainRequest),
        emitsError(
          isA<LlmException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.message, 'message', 'Quota exceeded'),
        ),
      );
    });

    test('an error in the middle of the stream', () async {
      final fake = sseFake([
        candidate([
          {'text': 'Hi'},
        ]),
        {
          'error': {'code': 503, 'message': 'The model is overloaded.'},
        },
        stop,
      ]);
      await expectLater(
        provider(fake).stream(plainRequest),
        emitsInOrder([
          isA<LlmTextDelta>(),
          emitsError(
            isA<LlmException>()
                .having((e) => e.statusCode, 'statusCode', isNull)
                .having((e) => e.message, 'message', 'The model is overloaded.')
                .having((e) => e.body, 'body', contains('503')),
          ),
          emitsDone,
        ]),
      );
    });

    test('a blocked prompt', () async {
      final fake = sseFake([
        {
          'promptFeedback': {'blockReason': 'SAFETY'},
        },
      ]);
      await expectLater(
        provider(fake).stream(plainRequest),
        emitsError(
          isA<LlmException>().having(
            (e) => e.message,
            'message',
            contains('SAFETY'),
          ),
        ),
      );
    });
  });

  test('cancel aborts the request', () async {
    final fake = sseFake([
      candidate([
        {'text': 'Hi'},
      ]),
    ], keepOpen: true);
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
