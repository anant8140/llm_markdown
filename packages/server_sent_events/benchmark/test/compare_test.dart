// Runs the same scenarios through server_sent_events and
// flutter_client_sse against one local server and prints what each did.
// Run: flutter test test/compare_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_sent_events/server_sent_events.dart';

late HttpServer server;
late String base;
var requests = 0;
Completer<void> socketClosed = Completer();

/// One row of the result table.
void row(String scenario, String ours, String theirs) =>
    // ignore: avoid_print
    print('RESULT | $scenario | $ours | $theirs');

Future<Socket> rawStream(HttpRequest request) async {
  request.response.headers
    ..contentType = ContentType('text', 'event-stream')
    ..contentLength = 100000000;
  final socket = await request.response.detachSocket();
  socket.listen(
    null,
    onDone: () {
      if (!socketClosed.isCompleted) socketClosed.complete();
      socket.destroy();
    },
    onError: (_) {},
  );
  return socket;
}

Future<void> handle(HttpRequest request) async {
  requests++;
  await request.drain<void>();
  final path = request.uri.path;
  final response = request.response;
  switch (path) {
    case '/many':
      response.headers.contentType = ContentType('text', 'event-stream');
      final n = int.parse(request.uri.queryParameters['n']!);
      final buffer = StringBuffer();
      for (var i = 0; i < n; i++) {
        buffer.write('data: {"i":$i,"text":"some words of a reply"}\n\n');
        if (i % 500 == 499) {
          response.write(buffer);
          buffer.clear();
          await response.flush();
        }
      }
      response.write(buffer);
      // "end" marks the last event for a client that can't see the end
      response.write('event: end\ndata: end\n\n');
      await response.close();
    case '/format':
      response.headers.contentType = ContentType('text', 'event-stream');
      response.write('data: hello\n\ndata: a\ndata: b\n\ndata:x\r\n\r\n');
      await response.close();
    case '/unknown':
      response.headers.contentType = ContentType('text', 'event-stream');
      response.write('foo: bar\ndata: ok\n\n');
      await response.close();
    case '/error':
      response
        ..statusCode = 401
        ..headers.contentType = ContentType.json
        ..write('{"error":{"message":"Invalid API key"}}');
      await response.close();
    case '/open':
      final socket = await rawStream(request);
      socket.add(utf8.encode('data: first\n\n'));
  }
}

/// What a stream gave within [wait]: its events' data, whether it ended,
/// and its error if any.
Future<({List<String> data, bool ended, Object? error})> watch(
  Stream<String?> stream, {
  Duration wait = const Duration(seconds: 2),
  int? stopAfter,
}) async {
  final data = <String>[];
  var ended = false;
  Object? error;
  final done = Completer<void>();
  final sub = stream.listen(
    (d) {
      data.add(d ?? '<null>');
      if (stopAfter != null && data.length >= stopAfter && !done.isCompleted) {
        done.complete();
      }
    },
    onError: (Object e) {
      error = e;
      if (!done.isCompleted) done.complete();
    },
    onDone: () {
      ended = true;
      if (!done.isCompleted) done.complete();
    },
  );
  await done.future.timeout(wait, onTimeout: () {});
  await sub.cancel();
  return (data: data, ended: ended, error: error);
}

Stream<String?> ours(String path) => connectSse(
  Uri.parse('$base$path'),
  reconnect: SseReconnect.none,
).map((e) => e.data);

Stream<String?> theirs(String path) => SSEClient.subscribeToSSE(
  method: SSERequestType.GET,
  url: '$base$path',
  header: const {},
).map((e) => e.data);

String show(List<String> data) => jsonEncode(data);

void main() {
  setUp(() async {
    requests = 0;
    socketClosed = Completer();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen(handle);
  });
  tearDown(() async {
    SSEClient.unsubscribeFromSSE();
    await server.close(force: true);
  });

  test('data as received', () async {
    final a = await watch(ours('/format'));
    final b = await watch(theirs('/format'));
    row(
      'data of `data: hello`, two data lines, `data:x` with CRLF',
      show(a.data),
      show(b.data),
    );
    row('stream ends when the server ends it', '${a.ended}', '${b.ended}');
  });

  test('an unknown field in the stream', () async {
    final a = await watch(ours('/unknown'));
    final ourRequests = requests;
    requests = 0;
    final b = await watch(theirs('/unknown'), wait: const Duration(seconds: 7));
    row(
      'unknown field `foo: bar` before an event',
      '${show(a.data)}, $ourRequests request',
      '${show(b.data)}, $requests requests in 7 s',
    );
  });

  test('an HTTP 401 with a JSON error body', () async {
    final a = await watch(ours('/error'));
    final ourRequests = requests;
    requests = 0;
    final b = await watch(theirs('/error'), wait: const Duration(seconds: 12));
    row(
      '401 with JSON body',
      'error: ${a.error.runtimeType} status ${(a.error as SseException?)?.statusCode}, body kept: ${(a.error as SseException?)?.body?.contains('Invalid API key')}, $ourRequests request',
      'error: ${b.error}, events: ${show(b.data)}, $requests requests in 12 s',
    );
  });

  test('cancelling the subscription', () async {
    await watch(ours('/open'), stopAfter: 1);
    final a = await socketClosed.future
        .then((_) => true)
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    socketClosed = Completer();
    await watch(theirs('/open'), stopAfter: 1);
    final b = await socketClosed.future
        .then((_) => true)
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    row(
      'connection closed within 3 s of cancelling the subscription',
      '$a',
      '$b',
    );
  });

  test('time for 50,000 events on one connection', () async {
    const n = 50000;
    Future<int> time(Stream<String?> stream) async {
      final clock = Stopwatch()..start();
      var count = 0;
      final done = Completer<void>();
      final sub = stream.listen(
        (d) {
          count++;
          if (d != null && d.trim() == 'end' && !done.isCompleted) {
            done.complete();
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 60));
      await sub.cancel();
      expect(count, greaterThanOrEqualTo(n));
      return clock.elapsedMilliseconds;
    }

    final ourTimes = <int>[];
    final theirTimes = <int>[];
    for (var run = 0; run < 3; run++) {
      ourTimes.add(await time(ours('/many?n=$n')));
      theirTimes.add(await time(theirs('/many?n=$n')));
    }
    row('50,000 events, 3 runs (ms)', '$ourTimes', '$theirTimes');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
