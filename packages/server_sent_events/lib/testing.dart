/// A fake HTTP client that answers with event streams, for testing code
/// that uses `server_sent_events` without a server.
///
/// ```dart
/// final fake = FakeSseClient((request) => FakeSseResponse.events([
///   const SseEvent('{"text": "Hi"}'),
///   const SseEvent('[DONE]'),
/// ]));
/// final events = connectSse(url, client: fake);
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'src/encoder.dart';
import 'src/event.dart';

/// What [FakeSseClient] answers a request with.
class FakeSseResponse {
  /// An event stream of [events], [delay] apart; with [keepOpen] the
  /// stream doesn't end after the last one, like a live feed.
  FakeSseResponse.events(
    List<SseEvent> events, {
    this.delay = Duration.zero,
    this.keepOpen = false,
    this.headers = const {},
  }) : statusCode = 200,
       _chunks = [for (final event in events) encodeSseEvent(event)];

  /// The raw text [chunks] of an event stream, sent as given, [delay]
  /// apart.
  FakeSseResponse.raw(
    List<String> chunks, {
    this.delay = Duration.zero,
    this.keepOpen = false,
    this.headers = const {},
  }) : statusCode = 200,
       _chunks = chunks;

  /// A failed request: [statusCode] with [body], such as the JSON error an
  /// API sends.
  FakeSseResponse.error(
    this.statusCode,
    String body, {
    this.headers = const {'content-type': 'application/json'},
  }) : delay = Duration.zero,
       keepOpen = false,
       _chunks = [body];

  /// The HTTP status.
  final int statusCode;

  /// The pause before each chunk.
  final Duration delay;

  /// Whether the body stays open after the last chunk.
  final bool keepOpen;

  /// Response headers; an event stream gets `text/event-stream` unless set.
  final Map<String, String> headers;

  final List<String> _chunks;
}

/// An [http.Client] that answers every request with what [respond] gives,
/// without a network; see [FakeSseResponse].
///
/// It keeps the [requests] it got, with their [bodies], and stops a
/// response when the request is aborted, as a real client does.
class FakeSseClient extends http.BaseClient {
  /// A client answering with [respond].
  FakeSseClient(this.respond);

  /// Gives the response to a request.
  final FutureOr<FakeSseResponse> Function(http.BaseRequest request) respond;

  /// The requests made, in order.
  final requests = <http.BaseRequest>[];

  /// The body of each of [requests], as text.
  final bodies = <String>[];

  /// How many responses were stopped early, by an abort or a cancel.
  var aborted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(await utf8.decodeStream(request.finalize()));
    final response = await respond(request);
    var stopped = false;
    final body = StreamController<List<int>>();
    void stop() {
      if (stopped) return;
      stopped = true;
      aborted++;
      if (!body.isClosed) body.close();
    }

    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.whenComplete(stop));
    }
    body.onCancel = stop;
    body.onListen = () async {
      for (final chunk in response._chunks) {
        if (response.delay > Duration.zero) {
          await Future<void>.delayed(response.delay);
        }
        if (stopped) return;
        body.add(utf8.encode(chunk));
      }
      if (!response.keepOpen && !stopped) {
        stopped = true;
        await body.close();
      }
    };
    return http.StreamedResponse(
      body.stream,
      response.statusCode,
      request: request,
      headers: {
        if (response.statusCode >= 200 && response.statusCode < 300)
          'content-type': 'text/event-stream',
        ...response.headers,
      },
    );
  }
}
