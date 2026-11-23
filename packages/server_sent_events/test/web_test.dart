@TestOn('browser')
library;

import 'package:server_sent_events/server_sent_events.dart';
import 'package:stream_channel/stream_channel.dart';
import "package:async/async.dart";
import "package:test/test.dart";

// Runs on the VM next to the browser: an SSE server that sends one event,
// waits for the test to say "more", then sends the rest. It reports when the
// browser closes the connection.
const _server = r'''
import 'dart:convert';
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final more = channel.stream.where((m) => m == 'more').asBroadcastStream();
  server.listen((request) async {
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST');
    if (request.method == 'OPTIONS') {
      await request.response.close();
      return;
    }
    final body = await utf8.decodeStream(request);
    request.response.headers
      ..contentType = ContentType('text', 'event-stream')
      ..contentLength = 100000;
    final socket = await request.response.detachSocket();
    socket.listen(null, onDone: () => channel.sink.add('closed'), onError: (_) {});
    socket.add(utf8.encode('data: got $body\n\n'));
    await socket.flush();
    if (request.uri.path == '/cancel') return;
    await more.first;
    socket.add(utf8.encode('data: rest\n\ndata: [DONE]\n\n'));
    await socket.flush();
  });
  channel.sink.add(server.port);
}
''';

void main() {
  late StreamChannel<Object?> channel;
  late StreamQueue<Object?> messages;
  late Uri base;

  setUp(() async {
    channel = spawnHybridCode(_server);
    messages = StreamQueue(channel.stream);
    base = Uri.parse('http://127.0.0.1:${await messages.next}/');
  });

  test('events arrive one by one in the browser, POST body sent', () async {
    final events = StreamQueue(
      connectSse(base, method: 'POST', body: 'hi').untilDone(),
    );
    // the first event comes before the server has sent the rest: the
    // browser client streams, it doesn't wait for the whole body
    expect((await events.next).data, 'got hi');
    channel.sink.add('more');
    expect((await events.next).data, 'rest');
    expect(await events.hasNext, isFalse);
  });

  test('cancelling closes the connection in the browser', () async {
    final first = await connectSse(base.resolve('/cancel')).first;
    expect(first.data, 'got ');
    expect(await messages.next.timeout(const Duration(seconds: 5)), 'closed');
  });
}
