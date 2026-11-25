@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server_sent_events/server_sent_events.dart';
import 'package:test/test.dart';

late HttpServer server;
late Uri base;
final requests = <HttpRequest>[];
final bodies = <String>[];
// the request handler of the current test
late Future<void> Function(HttpRequest request, int n) handle;
// completes when a response's connection is seen closing by the client
Completer<void> closed = Completer();

Future<void> stream(HttpResponse response, Iterable<String> parts) async {
  response.headers.contentType = ContentType('text', 'event-stream');
  response.bufferOutput = false;
  for (final part in parts) {
    response.write(part);
    await response.flush();
  }
}

// Sends [data] and then breaks the connection in the middle of the body,
// which the client sees as an error.
Future<void> dropAfter(HttpRequest request, String data) async {
  request.response.headers
    ..contentType = ContentType('text', 'event-stream')
    ..contentLength = 100000;
  final socket = await request.response.detachSocket();
  socket.add(utf8.encode(data));
  await socket.flush();
  socket.destroy();
}

void main() {
  setUp(() async {
    requests.clear();
    bodies.clear();
    closed = Completer();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://${server.address.host}:${server.port}/');
    var n = 0;
    server.listen((request) async {
      requests.add(request);
      bodies.add(await utf8.decodeStream(request));
      unawaited(
        request.response.done.then(
          (_) {},
          onError: (_) {
            if (!closed.isCompleted) closed.complete();
          },
        ),
      );
      await handle(request, n++);
    });
  });
  tearDown(() => server.close(force: true));

  test('POST with JSON body and headers; events until [DONE]', () async {
    handle = (request, _) async {
      await stream(request.response, [
        'data: {"t":"Hel"}\n\n',
        'data: {"t":"lo"}\n\n',
        'data: [DONE]\n\n',
      ]);
      await request.response.close();
    };
    final parts = await connectSse(
      base,
      method: 'POST',
      headers: {'Authorization': 'Bearer k'},
      body: {'stream': true},
    ).json().map((json) => (json! as Map)['t']).toList();
    expect(parts, ['Hel', 'lo']);
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.headers.value('authorization'), 'Bearer k');
    expect(request.headers.value('accept'), 'text/event-stream');
    expect(request.headers.contentType?.mimeType, 'application/json');
    expect(bodies.single, '{"stream":true}');
  });

  test('cancelling closes the connection at once', () async {
    handle = (request, _) async {
      request.response.headers
        ..contentType = ContentType('text', 'event-stream')
        ..contentLength = 100000;
      final socket = await request.response.detachSocket();
      socket.add(utf8.encode('data: first\n\n'));
      // the server would go on for long; the socket ends when the client
      // closes the connection
      socket.listen(
        null,
        onDone: () {
          if (!closed.isCompleted) closed.complete();
          socket.destroy();
        },
        onError: (_) {},
      );
    };
    final first = await connectSse(base).first;
    expect(first.data, 'first');
    await closed.future.timeout(const Duration(seconds: 5));
  });

  test('a body that is not JSON ends the stream with the error', () async {
    final statuses = <SseStatus>[];
    final error =
        await connectSse(
              base,
              method: 'POST',
              body: {'when': DateTime(2026)},
              onStatus: statuses.add,
            )
            .toList()
            .timeout(const Duration(seconds: 5))
            .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<JsonUnsupportedObjectError>());
    expect(statuses.last, SseStatus.closed);
    expect(requests, isEmpty);
  });

  test('an error status gives the body, and is not retried', () async {
    handle = (request, _) async {
      request.response
        ..statusCode = 401
        ..headers.contentType = ContentType.json
        ..write('{"error":{"message":"Invalid API key"}}');
      await request.response.close();
    };
    final error = await connectSse(
      base,
      reconnect: const SseReconnect(delay: Duration.zero),
    ).toList().then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<SseException>());
    error as SseException;
    expect(error.statusCode, 401);
    expect(error.body, contains('Invalid API key'));
    expect(requests, hasLength(1));
  });

  test('JSON with status 200 is an error too; 204 ends quietly', () async {
    handle = (request, n) async {
      if (n == 0) {
        request.response
          ..headers.contentType = ContentType.json
          ..write('{"error":"no stream"}');
      } else {
        request.response.statusCode = 204;
      }
      await request.response.close();
    };
    await expectLater(
      connectSse(base).toList(),
      throwsA(
        isA<SseException>().having(
          (e) => e.body,
          'body',
          '{"error":"no stream"}',
        ),
      ),
    );
    expect(await connectSse(base).toList(), isEmpty);
  });

  test(
    'a GET reconnects with Last-Event-ID after the connection drops',
    () async {
      handle = (request, n) async {
        if (n == 0) {
          await dropAfter(request, 'retry: 10\nid: 1\ndata: a\n\n');
        } else {
          await stream(request.response, ['id: 2\ndata: b\n\n']);
          await request.response.close();
        }
      };
      final watch = Stopwatch()..start();
      final events = await connectSse(base).toList();
      expect(events.map((e) => e.data), ['a', 'b']);
      expect(events.map((e) => e.id), ['1', '2']);
      expect(requests[1].headers.value('last-event-id'), '1');
      // the server's retry: 10 ms was used, not the default second
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 900)));
    },
  );

  test('a POST is not reconnected by default', () async {
    handle = (request, n) async {
      await dropAfter(request, 'data: a\n\n');
    };
    final events = <String>[];
    Object? error;
    await connectSse(
      base,
      method: 'POST',
      body: 'x',
    ).handleError((Object e) => error = e).forEach((e) => events.add(e.data));
    expect(events, ['a']);
    expect(error, isNotNull);
    expect(requests, hasLength(1));
  });

  test('a 503 is retried with growing waits, then given up', () async {
    handle = (request, _) async {
      request.response
        ..statusCode = 503
        ..write('busy');
      await request.response.close();
    };
    await expectLater(
      connectSse(
        base,
        reconnect: const SseReconnect(
          maxAttempts: 2,
          delay: Duration(milliseconds: 5),
        ),
      ).toList(),
      throwsA(isA<SseException>().having((e) => e.statusCode, 'status', 503)),
    );
    expect(requests, hasLength(3));
  });

  test('with onClose a stream ended by the server is opened again', () async {
    handle = (request, n) async {
      await stream(request.response, ['data: $n\n\n']);
      await request.response.close();
    };
    final events = await connectSse(
      base,
      reconnect: const SseReconnect(onClose: true, delay: Duration.zero),
    ).take(3).map((e) => e.data).toList();
    expect(events, ['0', '1', '2']);
  });

  test('a bad body is refused at once', () {
    expect(() => connectSse(base, body: 3), throwsArgumentError);
  });
}
