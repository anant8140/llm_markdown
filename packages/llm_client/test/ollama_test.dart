import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_client/llm_client.dart';
import 'package:server_sent_events/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

String line(Map<String, Object?> message, {bool done = false}) =>
    '${jsonEncode({'model': 'test-model', 'message': message, 'done': done})}\n';

String doneLine({String? reason = 'stop', int? input = 11, int? output = 6}) =>
    '${jsonEncode({
      'model': 'test-model',
      'message': {'role': 'assistant', 'content': ''},
      'done': true,
      'done_reason': ?reason,
      'prompt_eval_count': ?input,
      'eval_count': ?output,
    })}\n';

/// A fake answering with the NDJSON [chunks], sent as given.
FakeSseClient linesFake(List<String> chunks) => FakeSseClient(
  (_) => FakeSseResponse.raw(
    chunks,
    headers: const {'content-type': 'application/x-ndjson'},
  ),
);

/// An [http.Client] whose response stays open until the request is
/// aborted, as a real client behaves.
class HangingClient extends http.BaseClient {
  HangingClient(this.firstChunk);

  final String? firstChunk;
  final requests = <http.BaseRequest>[];
  var aborted = 0;
  var closed = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    await request.finalize().drain<void>();
    final body = StreamController<List<int>>();
    if (request is http.Abortable) {
      unawaited(
        request.abortTrigger?.whenComplete(() {
          aborted++;
          if (!body.isClosed) {
            body.addError(http.RequestAbortedException(request.url));
            body.close();
          }
        }),
      );
    }
    if (firstChunk != null) body.add(utf8.encode(firstChunk!));
    return http.StreamedResponse(body.stream, 200, request: request);
  }

  @override
  void close() => closed++;
}

/// An [http.Client] that never answers until the request is aborted.
class SilentClient extends http.BaseClient {
  var aborted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    final trigger = (request as http.Abortable).abortTrigger!;
    await trigger;
    aborted++;
    throw http.RequestAbortedException(request.url);
  }
}

void main() {
  group('request', () {
    test('plain chat: URL, headers and body', () async {
      final fake = linesFake([doneLine()]);
      await OllamaProvider(client: fake).stream(plainRequest).drain<void>();
      final request = sentRequest(fake);
      expect(request.method, 'POST');
      expect('${request.url}', 'http://localhost:11434/api/chat');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request, isA<http.Abortable>());
      expect(sentBody(fake), {
        'model': 'test-model',
        'messages': [
          {'role': 'system', 'content': 'Be brief.'},
          {'role': 'user', 'content': 'Hi'},
        ],
        'stream': true,
        'options': {'temperature': 0.5, 'num_predict': 100},
      });
    });

    test('base URL, headers, no options, extra fields last', () async {
      final fake = linesFake([doneLine()]);
      await OllamaProvider(
            baseUrl: 'https://ollama.example.com/',
            headers: {'Authorization': 'Bearer t'},
            client: fake,
          )
          .stream(
            const LlmRequest(
              model: 'm',
              messages: [LlmMessage.user('Hi')],
              extra: {'think': true},
            ),
          )
          .drain<void>();
      final request = sentRequest(fake);
      expect('${request.url}', 'https://ollama.example.com/api/chat');
      expect(request.headers['Authorization'], 'Bearer t');
      expect(sentBody(fake), {
        'model': 'm',
        'messages': [
          {'role': 'user', 'content': 'Hi'},
        ],
        'stream': true,
        'think': true,
      });
    });

    test('tools', () async {
      final fake = linesFake([doneLine()]);
      await OllamaProvider(client: fake).stream(toolRequest).drain<void>();
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

    test('tool round trip', () async {
      final fake = linesFake([doneLine()]);
      await OllamaProvider(client: fake).stream(roundTripRequest).drain<void>();
      expect(sentBody(fake)['messages'], [
        {'role': 'user', 'content': 'Weather in Paris and Rome?'},
        {
          'role': 'assistant',
          'content': 'Checking.',
          'tool_calls': [
            {
              'function': {
                'name': 'get_weather',
                'arguments': {'city': 'Paris'},
              },
            },
            {
              'function': {
                'name': 'get_weather',
                'arguments': {'city': 'Rome'},
              },
            },
          ],
        },
        {'role': 'tool', 'content': '{"temp": 21}', 'tool_name': 'get_weather'},
        {'role': 'tool', 'content': 'rain', 'tool_name': 'get_weather'},
      ]);
    });
  });

  group('stream', () {
    test('text, usage and finish reason; lines split across chunks', () async {
      final all =
          line({'role': 'assistant', 'content': 'Hel'}) +
          line({'role': 'assistant', 'content': 'lo'}) +
          doneLine();
      final fake = linesFake([
        all.substring(0, 20),
        all.substring(20, 97),
        all.substring(97),
      ]);
      expect(await collect(OllamaProvider(client: fake).stream(plainRequest)), [
        'text:Hel',
        'text:lo',
        'usage:11:6',
        'done:stop:stop',
      ]);
    });

    test('thinking, then text, cut off by the token limit', () async {
      final fake = linesFake([
        line({'role': 'assistant', 'content': '', 'thinking': 'Let me '}),
        line({'role': 'assistant', 'content': '', 'thinking': 'see.'}),
        line({'role': 'assistant', 'content': '42'}),
        doneLine(reason: 'length'),
      ]);
      expect(await collect(OllamaProvider(client: fake).stream(plainRequest)), [
        'thinking:Let me ',
        'thinking:see.',
        'text:42',
        'usage:11:6',
        'done:length:length',
      ]);
    });

    test('tool calls arrive whole, in several lines', () async {
      final fake = linesFake([
        line({
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'function': {
                'name': 'get_weather',
                'arguments': {'city': 'Paris'},
              },
            },
          ],
        }),
        line({
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call_x9',
              'function': {'name': 'get_time', 'arguments': {}},
            },
          ],
        }),
        doneLine(),
      ]);
      expect(await collect(OllamaProvider(client: fake).stream(toolRequest)), [
        'start:call_0:get_weather',
        'delta:call_0:{"city":"Paris"}:{"city":"Paris"}',
        'call:call_0:get_weather:{"city":"Paris"}',
        'start:call_x9:get_time',
        'delta:call_x9:{}:{}',
        'call:call_x9:get_time:{}',
        'usage:11:6',
        'done:toolCalls:stop',
      ]);
    });

    test('no usage event when the server counts nothing', () async {
      final fake = linesFake([doneLine(input: null, output: null)]);
      expect(await collect(OllamaProvider(client: fake).stream(plainRequest)), [
        'done:stop:stop',
      ]);
    });

    test('a stream cut off before done is an error', () async {
      final fake = linesFake([
        line({'role': 'assistant', 'content': 'Hi'}),
      ]);
      await expectLater(
        OllamaProvider(client: fake).stream(plainRequest),
        emitsInOrder([
          isA<LlmTextDelta>(),
          emitsError(isA<LlmException>()),
          emitsDone,
        ]),
      );
    });

    test('a line that is not JSON is an error', () async {
      final fake = linesFake(['<html>proxy</html>\n']);
      await expectLater(
        OllamaProvider(client: fake).stream(plainRequest),
        emitsError(
          isA<LlmException>().having(
            (e) => e.body,
            'body',
            '<html>proxy</html>',
          ),
        ),
      );
    });
  });

  group('errors', () {
    test('an HTTP error with a JSON body', () async {
      final fake = errorFake(404, {'error': 'model "nope" not found'});
      await expectLater(
        OllamaProvider(client: fake).stream(plainRequest),
        emitsInOrder([
          emitsError(
            isA<LlmException>()
                .having((e) => e.statusCode, 'statusCode', 404)
                .having((e) => e.message, 'message', 'model "nope" not found')
                .having((e) => e.body, 'body', contains('"error"')),
          ),
          emitsDone,
        ]),
      );
    });

    test('an HTTP error without JSON keeps the status and body', () async {
      final fake = errorFake(500, 'boom');
      await expectLater(
        OllamaProvider(client: fake).stream(plainRequest),
        emitsError(
          isA<LlmException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', contains('500'))
              .having((e) => e.body, 'body', 'boom'),
        ),
      );
    });

    test('an error line in the middle of the stream', () async {
      final fake = linesFake([
        line({'role': 'assistant', 'content': 'Hi'}),
        '{"error":"llama runner process has terminated"}\n',
        line({'role': 'assistant', 'content': ' never'}),
        doneLine(),
      ]);
      await expectLater(
        OllamaProvider(client: fake).stream(plainRequest),
        emitsInOrder([
          isA<LlmTextDelta>(),
          emitsError(
            isA<LlmException>()
                .having((e) => e.statusCode, 'statusCode', isNull)
                .having(
                  (e) => e.message,
                  'message',
                  'llama runner process has terminated',
                )
                .having((e) => e.body, 'body', contains('"error"')),
          ),
          emitsDone,
        ]),
      );
    });
  });

  group('cancel', () {
    test('aborts the request while the reply streams', () async {
      final client = HangingClient(
        line({'role': 'assistant', 'content': 'Hi'}),
      );
      final first = Completer<LlmEvent>();
      final errors = <Object>[];
      final subscription = OllamaProvider(
        client: client,
      ).stream(plainRequest).listen(first.complete, onError: errors.add);
      expect(describe(await first.future), 'text:Hi');
      expect(client.requests.single, isA<http.AbortableRequest>());
      expect(client.aborted, 0);
      await subscription.cancel();
      await pumpEventQueue();
      expect(client.aborted, 1);
      expect(errors, isEmpty);
      // a client given to the provider is not closed by it
      expect(client.closed, 0);
    });

    test('aborts the request before the server answers', () async {
      final client = SilentClient();
      final errors = <Object>[];
      final subscription = OllamaProvider(
        client: client,
      ).stream(plainRequest).listen((_) {}, onError: errors.add);
      await pumpEventQueue();
      expect(client.aborted, 0);
      await subscription.cancel();
      await pumpEventQueue();
      expect(client.aborted, 1);
      expect(errors, isEmpty);
    });

    test('a reply that finished is not aborted', () async {
      final client = HangingClient(
        line({'role': 'assistant', 'content': 'Hi'}) + doneLine(),
      );
      expect(
        await collect(OllamaProvider(client: client).stream(plainRequest)),
        ['text:Hi', 'usage:11:6', 'done:stop:stop'],
      );
      await pumpEventQueue();
      // the connection is still closed, since the server left it open
      expect(client.aborted, 1);
    });
  });
}
