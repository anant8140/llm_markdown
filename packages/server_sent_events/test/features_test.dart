import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:server_sent_events/server_sent_events.dart';
import 'package:server_sent_events/testing.dart';
import 'package:test/test.dart';

final url = Uri.parse('https://api.test/v1/chat');

SseEvent data(Object json) => SseEvent(jsonEncode(json));

void main() {
  group('SseClient', () {
    test('base URL, async shared headers, then the request\'s own', () async {
      var token = 'a';
      final fake = FakeSseClient(
        (_) => FakeSseResponse.events([const SseEvent('x')]),
      );
      final client = SseClient(
        baseUrl: Uri.parse('https://api.test/v1/'),
        client: fake,
        headers: () async => {'Authorization': 'Bearer $token', 'X-A': '1'},
      );
      await client.connect('chat', headers: {'X-A': '2'}).drain<void>();
      token = 'b';
      await client.connect(Uri.parse('other')).drain<void>();
      expect(fake.requests.map((r) => '${r.url}'), [
        'https://api.test/v1/chat',
        'https://api.test/v1/other',
      ]);
      expect(fake.requests[0].headers['Authorization'], 'Bearer a');
      expect(fake.requests[0].headers['X-A'], '2');
      expect(fake.requests[1].headers['Authorization'], 'Bearer b');
    });

    test('a 401 refreshes the token once and tries again', () async {
      var token = 'old';
      var refreshes = 0;
      final fake = FakeSseClient(
        (request) => request.headers['Authorization'] == 'Bearer new'
            ? FakeSseResponse.events([const SseEvent('ok')])
            : FakeSseResponse.error(401, '{"error":"expired"}'),
      );
      final client = SseClient(
        client: fake,
        headers: () => {'Authorization': 'Bearer $token'},
        onUnauthorized: () async {
          refreshes++;
          token = 'new';
          return true;
        },
      );
      final events = await client.connect(url, method: 'POST').toList();
      expect(events.single.data, 'ok');
      expect(refreshes, 1);
      expect(fake.requests, hasLength(2));

      // a refresh that doesn't help ends with the 401, without looping
      token = 'old';
      final stuck = SseClient(
        client: FakeSseClient((_) => FakeSseResponse.error(401, 'no')),
        onUnauthorized: () async => true,
      );
      await expectLater(
        stuck.connect(url).toList(),
        throwsA(isA<SseException>().having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('a refresh that gives false ends with the 401', () async {
      final client = SseClient(
        client: FakeSseClient((_) => FakeSseResponse.error(401, 'no')),
        onUnauthorized: () async => false,
      );
      await expectLater(
        client.connect(url).toList(),
        throwsA(isA<SseException>()),
      );
    });
  });

  group('status', () {
    test('connecting, open, closed', () async {
      final seen = <SseStatus>[];
      await connectSse(
        url,
        client: FakeSseClient(
          (_) => FakeSseResponse.events([const SseEvent('a')]),
        ),
        onStatus: seen.add,
      ).drain<void>();
      expect(seen, [SseStatus.connecting, SseStatus.open, SseStatus.closed]);
    });

    test('reconnecting between two opens; closed on cancel', () async {
      final seen = <SseStatus>[];
      var n = 0;
      final events = connectSse(
        url,
        client: FakeSseClient(
          (_) => n++ == 0
              ? FakeSseResponse.error(503, 'busy', headers: const {})
              : FakeSseResponse.events([const SseEvent('a')], keepOpen: true),
        ),
        reconnect: const SseReconnect(delay: Duration.zero, jitter: 0),
        onStatus: seen.add,
      );
      await events.first;
      expect(seen, [
        SseStatus.connecting,
        SseStatus.reconnecting,
        SseStatus.open,
        SseStatus.closed,
      ]);
    });
  });

  group('timeouts', () {
    test('idleTimeout drops a quiet connection', () async {
      final fake = FakeSseClient(
        (_) => FakeSseResponse.events([const SseEvent('a')], keepOpen: true),
      );
      final got = <String>[];
      Object? error;
      await connectSse(
        url,
        client: fake,
        idleTimeout: const Duration(milliseconds: 50),
        reconnect: SseReconnect.none,
      ).handleError((Object e) => error = e).forEach((e) => got.add(e.data));
      expect(got, ['a']);
      expect(error, isA<TimeoutException>());
      expect(fake.aborted, 1);
    });

    test('idleTimeout with reconnect opens it again', () async {
      final fake = FakeSseClient(
        (_) => FakeSseResponse.events([const SseEvent('a')], keepOpen: true),
      );
      final got = await connectSse(
        url,
        client: fake,
        idleTimeout: const Duration(milliseconds: 30),
        reconnect: const SseReconnect(delay: Duration.zero, jitter: 0),
      ).take(2).map((e) => e.data).toList();
      expect(got, ['a', 'a']);
      expect(fake.requests, hasLength(2));
    });

    test('connectTimeout gives up on a server that does not answer', () async {
      final fake = FakeSseClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return FakeSseResponse.events(const []);
      });
      final watch = Stopwatch()..start();
      await expectLater(
        connectSse(
          url,
          client: fake,
          connectTimeout: const Duration(milliseconds: 50),
          reconnect: SseReconnect.none,
        ).toList(),
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  test('Retry-After is waited for, longer than the policy\'s delay', () async {
    var n = 0;
    final watch = Stopwatch()..start();
    final events = await connectSse(
      url,
      client: FakeSseClient(
        (_) => n++ == 0
            ? FakeSseResponse.error(
                429,
                'slow down',
                headers: const {'retry-after': '1'},
              )
            : FakeSseResponse.events([const SseEvent('a')]),
      ),
      reconnect: const SseReconnect(delay: Duration.zero, jitter: 0),
    ).toList();
    expect(events.single.data, 'a');
    expect(watch.elapsed, greaterThan(const Duration(milliseconds: 900)));
  });

  test('waitBefore: grows, is capped, varies by jitter, obeys the server', () {
    const policy = SseReconnect(
      delay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 5),
      jitter: 0.5,
    );
    Duration wait(
      int failures,
      double roll, {
      Duration? server,
      Duration? after,
    }) => policy.waitBefore(
      failures,
      serverDelay: server,
      retryAfter: after,
      random: _Fixed(roll),
    );
    // a roll of 0.5 is the middle: no change
    expect(wait(0, 0.5), const Duration(seconds: 1));
    expect(wait(1, 0.5), const Duration(seconds: 2));
    expect(wait(2, 0.5), const Duration(seconds: 4));
    expect(wait(3, 0.5), const Duration(seconds: 5)); // capped
    // the ends of the range: half shorter, half longer
    expect(wait(0, 0), const Duration(milliseconds: 500));
    expect(wait(1, 1), const Duration(seconds: 3));
    // the server's retry: replaces the delay; Retry-After is a minimum
    expect(
      wait(0, 0.5, server: const Duration(seconds: 3)),
      const Duration(seconds: 3),
    );
    expect(
      wait(0, 0.5, after: const Duration(seconds: 9)),
      const Duration(seconds: 9),
    );
    expect(
      wait(0, 0.5, after: const Duration(milliseconds: 1)),
      const Duration(seconds: 1),
    );
    // without jitter the random is not used
    expect(
      const SseReconnect(jitter: 0).waitBefore(1, random: _Fixed(0)),
      const Duration(seconds: 2),
    );
  });

  test('maxEventSize ends a too large event without retrying', () async {
    final fake = FakeSseClient(
      (_) => FakeSseResponse.raw([
        'data: ok\n\n',
        'data: ${'x' * 500}',
        'yyy\n\n',
      ]),
    );
    final got = <String>[];
    Object? error;
    await connectSse(
      url,
      client: fake,
      maxEventSize: 100,
      reconnect: const SseReconnect(delay: Duration.zero),
    ).handleError((Object e) => error = e).forEach((e) => got.add(e.data));
    expect(got, ['ok']);
    expect('$error', contains('larger than 100'));
    expect(fake.requests, hasLength(1));
  });

  test('onLine sees every line, comments too', () async {
    final lines = <String>[];
    await connectSse(
      url,
      client: FakeSseClient(
        (_) => FakeSseResponse.raw([': hi\nevent: a\ndata: 1\n\n']),
      ),
      onLine: lines.add,
    ).drain<void>();
    expect(lines, [': hi', 'event: a', 'data: 1', '']);
  });

  test('ofType keeps only one event type', () async {
    final events = connectSse(
      url,
      client: FakeSseClient(
        (_) => FakeSseResponse.events([
          const SseEvent('1', event: 'a'),
          const SseEvent('2', event: 'b'),
          const SseEvent('3', event: 'a'),
        ]),
      ),
    );
    expect(await events.ofType('a').map((e) => e.data).toList(), ['1', '3']);
  });

  group('AI text', () {
    Stream<SseEvent> stream(List<SseEvent> events) => connectSse(
      url,
      client: FakeSseClient((_) => FakeSseResponse.events(events)),
    );

    test('OpenAI Chat Completions and Responses API', () async {
      expect(
        await stream([
          data({'choices': []}),
          data({
            'choices': [
              {
                'delta': {'role': 'assistant'},
              },
            ],
          }),
          data({
            'choices': [
              {
                'delta': {'content': 'Hel'},
              },
            ],
          }),
          data({
            'choices': [
              {
                'delta': {'content': 'lo'},
              },
            ],
          }),
          const SseEvent('[DONE]'),
          data({
            'choices': [
              {
                'delta': {'content': 'after done'},
              },
            ],
          }),
        ]).openAIText().join(),
        'Hello',
      );
      expect(
        await stream([
          data({'type': 'response.created'}),
          data({'type': 'response.output_text.delta', 'delta': 'Hi'}),
          data({'type': 'response.output_text.delta', 'delta': '!'}),
          data({'type': 'response.completed'}),
        ]).openAIText().join(),
        'Hi!',
      );
      await expectLater(
        stream([
          data({
            'error': {'message': 'Rate limit'},
          }),
        ]).openAIText().toList(),
        throwsA(
          isA<SseException>().having((e) => e.message, 'm', 'Rate limit'),
        ),
      );
    });

    test('Anthropic text deltas up to message_stop; errors', () async {
      expect(
        await stream([
          data({'type': 'message_start'}).withEvent('message_start'),
          data({
            'delta': {'type': 'thinking_delta', 'thinking': 'hmm'},
          }).withEvent('content_block_delta'),
          data({
            'delta': {'type': 'text_delta', 'text': 'Hey'},
          }).withEvent('content_block_delta'),
          data({}).withEvent('message_stop'),
          data({
            'delta': {'type': 'text_delta', 'text': 'late'},
          }).withEvent('content_block_delta'),
        ]).anthropicText().join(),
        'Hey',
      );
      await expectLater(
        stream([
          data({
            'type': 'error',
            'error': {'message': 'Overloaded'},
          }).withEvent('error'),
        ]).anthropicText().toList(),
        throwsA(
          isA<SseException>().having((e) => e.message, 'm', 'Overloaded'),
        ),
      );
    });

    test('Gemini text without thoughts; a block is an error', () async {
      expect(
        await stream([
          data({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'thinking', 'thought': true},
                    {'text': 'Answer'},
                  ],
                },
              },
            ],
          }),
          data({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '.'},
                  ],
                },
              },
            ],
          }),
        ]).geminiText().join(),
        'Answer.',
      );
      await expectLater(
        stream([
          data({
            'promptFeedback': {'blockReason': 'SAFETY'},
          }),
        ]).geminiText().toList(),
        throwsA(
          isA<SseException>().having((e) => e.message, 'm', 'Blocked: SAFETY'),
        ),
      );
    });
  });

  group('encoder', () {
    test('writes the format; refuses line breaks in type and id', () {
      expect(
        encodeSseEvent(
          const SseEvent(
            'a\nb\r\nc',
            event: 'add',
            id: '7',
            retry: Duration(seconds: 2),
          ),
        ),
        'event: add\nid: 7\nretry: 2000\ndata: a\ndata: b\ndata: c\n\n',
      );
      expect(encodeSseEvent(const SseEvent('')), 'data: \n\n');
      expect(encodeSseComment(), ':\n\n');
      expect(encodeSseComment('ping'), ': ping\n\n');
      expect(
        () => encodeSseEvent(const SseEvent('x', event: 'a\nb')),
        throwsArgumentError,
      );
      expect(
        () => encodeSseEvent(const SseEvent('x', id: 'a\rb')),
        throwsArgumentError,
      );
      expect(() => encodeSseComment('a\nb'), throwsArgumentError);
    });

    test('what it writes decodes to the same events', () async {
      final random = Random(3);
      const pieces = ['a', ' ', ':', 'é', '👋', '\n', '\r\n', 'data: x', ''];
      for (var round = 0; round < 200; round++) {
        final events = [
          for (var i = random.nextInt(5) + 1; i > 0; i--)
            SseEvent(
              [
                for (var j = random.nextInt(6); j > 0; j--)
                  pieces[random.nextInt(pieces.length)],
              ].join().replaceAll('\r\n', '\n'),
              event: random.nextBool() ? 'message' : 'e${random.nextInt(3)}',
              id: random.nextBool() ? null : 'id${random.nextInt(9)}',
            ),
        ];
        final text = events.map(encodeSseEvent).join();
        final bytes = utf8.encode(text);
        // split the bytes anywhere, even inside a character
        final chunks = <List<int>>[];
        for (var i = 0; i < bytes.length;) {
          final n = random.nextInt(7) + 1;
          chunks.add(bytes.sublist(i, min(i + n, bytes.length)));
          i += n;
        }
        final decoded = await Stream<List<int>>.fromIterable(
          chunks,
        ).transform(const SseDecoder()).toList();
        // an id lasts until changed, as the format says
        String? id;
        final expected = [
          for (final e in events)
            SseEvent(e.data, event: e.event, id: id = e.id ?? id),
        ];
        expect(decoded, expected, reason: text);
      }
    });

    test('keepAlive sends a comment when quiet', () async {
      final events = StreamController<SseEvent>();
      final out = <String>[];
      final sub = events.stream
          .transform(const SseEncoder(keepAlive: Duration(milliseconds: 40)))
          .listen(out.add);
      events.add(const SseEvent('a'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await events.close();
      await sub.asFuture<void>();
      expect(out.first, 'data: a\n\n');
      expect(out.skip(1), everyElement(':\n\n'));
      expect(out.length, greaterThanOrEqualTo(2));
    });
  });

  test(
    'the fake client stops a response when the stream is cancelled',
    () async {
      final fake = FakeSseClient(
        (_) => FakeSseResponse.events([const SseEvent('a')], keepOpen: true),
      );
      await connectSse(url, client: fake, method: 'POST', body: {'q': 1}).first;
      expect(fake.aborted, 1);
      expect(fake.bodies.single, '{"q":1}');
    },
  );
}

class _Fixed implements Random {
  _Fixed(this.roll);
  final double roll;
  @override
  double nextDouble() => roll;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

extension on SseEvent {
  SseEvent withEvent(String type) => SseEvent(this.data, event: type);
}
