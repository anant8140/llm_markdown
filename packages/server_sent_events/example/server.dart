import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server_sent_events/server_sent_events.dart';

/// An SSE server with `dart:io`: `dart run example/server.dart`, then open
/// http://localhost:8080/ or connect with [connectSse].
///
/// With shelf it is the same stream as the body of a response:
/// `Response.ok(bytes, headers: {'content-type': 'text/event-stream'},
/// context: {'shelf.io.buffer_output': false})`.
Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8080 : int.parse(args.first);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  print('Listening on http://localhost:${server.port}/');
  await for (final request in server) {
    // one tick a second, five times, with an id so a client can resume
    final start = int.tryParse(request.headers.value('last-event-id') ?? '');
    final ticks = Stream.periodic(
      const Duration(seconds: 1),
      (i) => SseEvent(
        jsonEncode({'tick': (start ?? 0) + i + 1}),
        event: 'tick',
        id: '${(start ?? 0) + i + 1}',
      ),
    ).take(5);

    request.response
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set('Cache-Control', 'no-cache')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..bufferOutput = false;
    unawaited(
      ticks
          .transform(const SseEncoder(keepAlive: Duration(seconds: 15)))
          .transform(utf8.encoder)
          .pipe(request.response)
          .catchError((Object _) {}), // the client went away
    );
  }
}
