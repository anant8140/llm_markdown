import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'decoder.dart';
import 'event.dart';

/// When and how often a dropped event stream is opened again.
class SseReconnect {
  /// Reconnects up to [maxAttempts] times in a row, waiting [delay] at
  /// first (or the server's `retry:` time) and [factor] times longer after
  /// each failed attempt, up to [maxDelay].
  ///
  /// It reconnects after a network error and after a 408, 429 or 5xx
  /// status; with [onClose] also when the server ends the stream normally,
  /// as a browser's `EventSource` does. An event received resets the count.
  const SseReconnect({
    this.maxAttempts = 5,
    this.delay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.factor = 2,
    this.onClose = false,
  });

  /// Never reconnects.
  static const none = SseReconnect(maxAttempts: 0);

  /// Reconnects whenever the stream ends, like a browser's `EventSource`.
  static const always = SseReconnect(maxAttempts: 1 << 30, onClose: true);

  /// The most attempts in a row before the error is given up on.
  final int maxAttempts;

  /// The wait before the first attempt, until the server sets one.
  final Duration delay;

  /// The longest wait.
  final Duration maxDelay;

  /// How much longer each wait after a failed attempt is.
  final double factor;

  /// Whether a stream the server ended normally is opened again.
  final bool onClose;
}

/// Opens an event stream at [url] and gives its events.
///
/// The request starts when the stream is listened to. [method], [headers]
/// and [body] are sent as given, so a `POST` with a JSON body works, as AI
/// APIs need; a [body] that is a [Map] or [List] is sent as JSON. The
/// request asks for `text/event-stream` unless [headers] says otherwise.
///
/// A status that isn't 2xx, or a JSON response instead of an event stream,
/// ends the stream with an [SseException] holding the start of the body,
/// so the error an API sends can be shown. Status 204 ends it without an
/// error.
///
/// Cancelling the subscription aborts the request and closes the
/// connection. With [reconnect] it is opened again after it drops, with
/// the `Last-Event-ID` header set; by default only a `GET` request is
/// reconnected, since sending a `POST` again may start a new AI reply.
///
/// Give [client] to reuse one, for example one with your own settings or
/// a mock in tests; otherwise one is made for the stream and closed with
/// it. On the web the default client streams through `fetch`.
Stream<SseEvent> connectSse(
  Uri url, {
  String method = 'GET',
  Map<String, String>? headers,
  Object? body,
  http.Client? client,
  SseReconnect? reconnect,
  String? lastEventId,
}) {
  if (body != null && body is! String && body is! List && body is! Map) {
    throw ArgumentError.value(body, 'body', 'not a String, bytes or JSON');
  }
  final policy =
      reconnect ??
      (method.toUpperCase() == 'GET'
          ? const SseReconnect()
          : SseReconnect.none);
  late final StreamController<SseEvent> out;
  final ownClient = client == null;
  final http.Client http_ = client ?? http.Client();
  StreamSubscription<SseEvent>? events;
  Completer<void>? abort;
  Timer? wait;
  var cancelled = false;
  var failures = 0;
  var id = lastEventId;
  Duration? serverDelay;

  void close() {
    wait?.cancel();
    if (ownClient) http_.close();
    if (!out.isClosed) out.close();
  }

  late void Function() open;

  // Reconnects if [policy] allows it, otherwise ends with [error].
  void retry(Object? error, [StackTrace? stackTrace]) {
    events = null;
    if (cancelled) return;
    if (failures >= policy.maxAttempts) {
      if (error != null) out.addError(error, stackTrace);
      close();
      return;
    }
    var pause = serverDelay ?? policy.delay;
    for (var i = 0; i < failures; i++) {
      pause *= policy.factor;
    }
    if (pause > policy.maxDelay) pause = policy.maxDelay;
    failures++;
    wait = Timer(pause, open);
  }

  open = () async {
    if (cancelled) return;
    final trigger = abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      url,
      abortTrigger: trigger.future,
    );
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';
    if (headers != null) request.headers.addAll(headers);
    if (id != null) request.headers['Last-Event-ID'] = id!;
    switch (body) {
      case null:
        break;
      case String text:
        request.body = text;
      case List<int> bytes:
        request.bodyBytes = bytes;
      default:
        request.headers.putIfAbsent('Content-Type', () => 'application/json');
        request.body = jsonEncode(body);
    }

    final http.StreamedResponse response;
    try {
      response = await http_.send(request);
    } catch (error, stackTrace) {
      if (cancelled) return;
      retry(error, stackTrace);
      return;
    }
    if (cancelled) {
      unawaited(response.stream.listen(null).cancel());
      return;
    }
    final status = response.statusCode;
    final type = response.headers['content-type'] ?? '';
    if (status == 204) {
      unawaited(response.stream.listen(null).cancel());
      close();
      return;
    }
    if (status < 200 || status > 299 || type.contains('application/json')) {
      final text = await _start(response.stream);
      if (cancelled) return;
      final error = SseException(
        status < 200 || status > 299
            ? 'HTTP $status from $url'
            : 'Expected an event stream from $url, got $type',
        statusCode: status,
        body: text,
      );
      if (status == 408 || status == 429 || status >= 500) {
        retry(error);
      } else {
        out.addError(error);
        close();
      }
      return;
    }

    events = response.stream
        .transform(
          SseDecoder(
            lastEventId: id,
            onRetry: (retry) => serverDelay = retry,
            onLastEventId: (value) => id = value,
          ),
        )
        .listen(
          (event) {
            failures = 0;
            out.add(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            final current = events;
            events = null;
            unawaited(current?.cancel());
            if (cancelled) return;
            retry(error, stackTrace);
          },
          onDone: () {
            events = null;
            if (cancelled) return;
            if (policy.onClose) {
              retry(null);
            } else {
              close();
            }
          },
        );
    if (out.isPaused) events!.pause();
  };

  out = StreamController<SseEvent>(
    onListen: open,
    onPause: () => events?.pause(),
    onResume: () => events?.resume(),
    onCancel: () async {
      cancelled = true;
      wait?.cancel();
      final trigger = abort;
      if (trigger != null && !trigger.isCompleted) trigger.complete();
      final current = events;
      events = null;
      if (ownClient) http_.close();
      await current?.cancel();
    },
  );
  return out.stream;
}

// The first 64 KB of an error body, as text.
Future<String> _start(Stream<List<int>> body) async {
  const limit = 64 * 1024;
  final bytes = <int>[];
  try {
    await for (final chunk in body) {
      bytes.addAll(chunk);
      if (bytes.length >= limit) break;
    }
  } catch (_) {
    // keep what came
  }
  return utf8.decode(
    bytes.length > limit ? bytes.sublist(0, limit) : bytes,
    allowMalformed: true,
  );
}

/// Helpers for AI streams.
extension SseEventStream on Stream<SseEvent> {
  /// The events up to, not including, a `[DONE]` event; the stream (and
  /// the request) ends there.
  Stream<SseEvent> untilDone() => takeWhile((event) => !event.isDone);

  /// The `data` of each event up to `[DONE]`, decoded as JSON.
  Stream<Object?> json() => untilDone().map((event) => event.json);
}
