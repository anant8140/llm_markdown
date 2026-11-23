import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import 'decoder.dart';
import 'event.dart';

/// When and how often a dropped event stream is opened again.
class SseReconnect {
  /// Reconnects up to [maxAttempts] times in a row, waiting [delay] at
  /// first (or the server's `retry:` time) and [factor] times longer after
  /// each failed attempt, up to [maxDelay]. Each wait is made up to
  /// [jitter] (a fraction) longer or shorter at random, so many apps that
  /// lost the same server don't all come back at the same moment.
  ///
  /// It reconnects after a network error, a timeout, and a 408, 429 or 5xx
  /// status, waiting at least as long as a `Retry-After` header asks; with
  /// [onClose] also when the server ends the stream normally, as a
  /// browser's `EventSource` does. An event received resets the count.
  const SseReconnect({
    this.maxAttempts = 5,
    this.delay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.factor = 2,
    this.jitter = 0.1,
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

  /// The longest wait, apart from a longer `Retry-After`.
  final Duration maxDelay;

  /// How much longer each wait after a failed attempt is.
  final double factor;

  /// How much each wait may vary at random, as a fraction: 0.1 is ±10%.
  final double jitter;

  /// Whether a stream the server ended normally is opened again.
  final bool onClose;
}

/// The state of an event stream's connection, for showing it in an app.
enum SseStatus {
  /// The request is being made.
  connecting,

  /// The server answered with an event stream; events can arrive.
  open,

  /// The connection dropped and a new one is waiting to be made.
  reconnecting,

  /// The stream ended: done, cancelled or failed.
  closed,
}

/// Opens event streams, with settings shared by all of them: a base URL,
/// headers, a way to refresh an expired token, timeouts and limits.
///
/// ```dart
/// final client = SseClient(
///   baseUrl: Uri.parse('https://api.example.com/v1/'),
///   headers: () async => {'Authorization': 'Bearer ${await token()}'},
///   onUnauthorized: () async => refreshToken(),
/// );
/// final events = client.connect('chat', method: 'POST', body: {...});
/// ```
///
/// Call [close] when done with it, unless you gave the [http.Client].
class SseClient {
  /// A client; see the fields for what each setting does.
  SseClient({
    this.baseUrl,
    this.headers,
    this.onUnauthorized,
    http.Client? client,
    this.reconnect,
    this.connectTimeout,
    this.idleTimeout,
    this.maxEventSize,
    this.onLine,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// Relative paths given to [connect] are resolved against this.
  final Uri? baseUrl;

  /// Headers sent with every request, built again for each one, so a
  /// token that changed is picked up; may be async.
  final FutureOr<Map<String, String>> Function()? headers;

  /// Called after a 401 status; when it gives true (for example after
  /// refreshing a token) the request is made once more, with [headers]
  /// built again.
  final Future<bool> Function()? onUnauthorized;

  /// When to reconnect by default; see [connect].
  final SseReconnect? reconnect;

  /// How long to wait for the server to answer before giving up on the
  /// attempt (which [reconnect] may retry). No limit when null.
  final Duration? connectTimeout;

  /// How long the stream may go without receiving anything, comments and
  /// keep-alives included, before the connection counts as dead and is
  /// dropped (and maybe reopened). No limit when null.
  final Duration? idleTimeout;

  /// The most characters one event may have; see
  /// [SseDecoder.maxEventSize].
  final int? maxEventSize;

  /// Called with every line received, for logging; see [SseDecoder.onLine].
  final void Function(String line)? onLine;

  final http.Client _client;
  final bool _ownsClient;

  /// Closes the [http.Client] if this client made it. Streams still open
  /// end with an error.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Opens an event stream at [url], a [Uri] or a [String], resolved
  /// against [baseUrl], and gives its events.
  ///
  /// The request starts when the stream is listened to. [method],
  /// [headers] and [body] are sent as given, after the client's headers;
  /// a [body] that is a [Map] or [List] is sent as JSON. The request asks
  /// for `text/event-stream` unless the headers say otherwise.
  ///
  /// A status that isn't 2xx, or a JSON response instead of an event
  /// stream, ends the stream with an [SseException] holding the start of
  /// the body. Status 204 ends it without an error.
  ///
  /// Cancelling the subscription aborts the request and closes the
  /// connection. With [reconnect] (by default the client's, else only for
  /// `GET`, since sending a `POST` again may start a new AI reply) it is
  /// opened again after it drops, with `Last-Event-ID` set.
  ///
  /// [onStatus] is told when the connection opens, drops and closes.
  Stream<SseEvent> connect(
    Object url, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
    SseReconnect? reconnect,
    String? lastEventId,
    void Function(SseStatus status)? onStatus,
  }) {
    if (body != null && body is! String && body is! List && body is! Map) {
      throw ArgumentError.value(body, 'body', 'not a String, bytes or JSON');
    }
    final target = switch (url) {
      Uri() => baseUrl?.resolveUri(url) ?? url,
      String() => baseUrl?.resolve(url) ?? Uri.parse(url),
      _ => throw ArgumentError.value(url, 'url', 'not a Uri or String'),
    };
    return _Connection(
      this,
      target,
      method,
      headers,
      body,
      reconnect ??
          this.reconnect ??
          (method.toUpperCase() == 'GET'
              ? const SseReconnect()
              : SseReconnect.none),
      lastEventId,
      onStatus,
    ).stream;
  }
}

class _Connection {
  _Connection(
    this.client,
    this.url,
    this.method,
    this.headers,
    this.body,
    this.policy,
    this.id,
    this.onStatus,
  ) {
    out = StreamController<SseEvent>(
      onListen: () => _open(),
      onPause: () => events?.pause(),
      onResume: () => events?.resume(),
      onCancel: _cancel,
    );
  }

  final SseClient client;
  final Uri url;
  final String method;
  final Map<String, String>? headers;
  final Object? body;
  final SseReconnect policy;
  final void Function(SseStatus status)? onStatus;
  String? id;

  late final StreamController<SseEvent> out;
  Stream<SseEvent> get stream => out.stream;

  StreamSubscription<SseEvent>? events;
  Completer<void>? abort;
  Timer? wait;
  var cancelled = false;
  var failures = 0;
  var refreshed = false;
  SseStatus? status;
  Duration? serverDelay;
  // a Retry-After the server sent with the last failed attempt
  Duration? retryAfter;

  static final _random = Random();

  void _status(SseStatus next) {
    if (status == next) return;
    status = next;
    onStatus?.call(next);
  }

  void _abort() {
    final trigger = abort;
    if (trigger != null && !trigger.isCompleted) trigger.complete();
  }

  void _close([Object? error, StackTrace? stackTrace]) {
    wait?.cancel();
    _abort();
    if (!out.isClosed) {
      if (error != null) out.addError(error, stackTrace);
      out.close();
    }
    _status(SseStatus.closed);
  }

  Future<void> _cancel() async {
    cancelled = true;
    wait?.cancel();
    _abort();
    final current = events;
    events = null;
    _status(SseStatus.closed);
    await current?.cancel();
  }

  // Reconnects if the policy allows it, otherwise ends with [error].
  void _retry(Object? error, [StackTrace? stackTrace]) {
    events = null;
    _abort();
    if (cancelled) return;
    if (failures >= policy.maxAttempts) {
      _close(error, stackTrace);
      return;
    }
    var pause = serverDelay ?? policy.delay;
    for (var i = 0; i < failures; i++) {
      pause *= policy.factor;
    }
    if (pause > policy.maxDelay) pause = policy.maxDelay;
    if (policy.jitter > 0) {
      pause *= 1 + (_random.nextDouble() * 2 - 1) * policy.jitter;
    }
    final after = retryAfter;
    retryAfter = null;
    if (after != null && after > pause) pause = after;
    failures++;
    _status(SseStatus.reconnecting);
    wait = Timer(pause, _open);
  }

  Future<void> _open() async {
    if (cancelled) return;
    if (status != SseStatus.reconnecting) _status(SseStatus.connecting);
    final trigger = abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      url,
      abortTrigger: trigger.future,
    );
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';
    try {
      final shared = client.headers;
      if (shared != null) request.headers.addAll(await shared());
    } catch (error, stackTrace) {
      _close(error, stackTrace);
      return;
    }
    if (cancelled) return;
    final own = headers;
    if (own != null) request.headers.addAll(own);
    final last = id;
    if (last != null) request.headers['Last-Event-ID'] = last;
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
      final sent = client._client.send(request);
      final timeout = client.connectTimeout;
      response = timeout == null
          ? await sent
          : await sent.timeout(
              timeout,
              onTimeout: () {
                _abort();
                throw TimeoutException(
                  'No answer from $url within $timeout',
                  timeout,
                );
              },
            );
    } catch (error, stackTrace) {
      if (cancelled) return;
      _retry(error, stackTrace);
      return;
    }
    if (cancelled) {
      unawaited(response.stream.listen(null).cancel());
      return;
    }
    final code = response.statusCode;
    final type = response.headers['content-type'] ?? '';
    if (code == 204) {
      unawaited(response.stream.listen(null).cancel());
      _close();
      return;
    }
    if (code < 200 || code > 299 || type.contains('application/json')) {
      final text = await _start(response.stream);
      if (cancelled) return;
      final error = SseException(
        code < 200 || code > 299
            ? 'HTTP $code from $url'
            : 'Expected an event stream from $url, got $type',
        statusCode: code,
        body: text,
      );
      final refresh = client.onUnauthorized;
      if (code == 401 && refresh != null && !refreshed) {
        refreshed = true;
        bool again;
        try {
          again = await refresh();
        } catch (_) {
          again = false;
        }
        if (cancelled) return;
        if (again) {
          unawaited(_open());
        } else {
          _close(error);
        }
        return;
      }
      if (code == 408 || code == 429 || code >= 500) {
        retryAfter = _parseRetryAfter(response.headers['retry-after']);
        _retry(error);
      } else {
        _close(error);
      }
      return;
    }

    _status(SseStatus.open);
    refreshed = false;
    final idle = client.idleTimeout;
    var bytes = response.stream as Stream<List<int>>;
    if (idle != null) {
      bytes = bytes.timeout(
        idle,
        onTimeout: (sink) {
          sink.addError(
            TimeoutException('Nothing received from $url for $idle', idle),
          );
          sink.close();
        },
      );
    }
    events = bytes
        .transform(
          SseDecoder(
            lastEventId: id,
            onRetry: (retry) => serverDelay = retry,
            onLastEventId: (value) => id = value,
            onLine: client.onLine,
            maxEventSize: client.maxEventSize,
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
            if (error is SseException) {
              // a too large event: the server is broken, don't retry
              _close(error, stackTrace);
            } else {
              _retry(error, stackTrace);
            }
          },
          onDone: () {
            events = null;
            if (cancelled || out.isClosed) return;
            if (policy.onClose) {
              _retry(null);
            } else {
              _close();
            }
          },
        );
    if (out.isPaused) events!.pause();
  }
}

// A Retry-After header: seconds, or an HTTP date.
Duration? _parseRetryAfter(String? value) {
  if (value == null) return null;
  final seconds = int.tryParse(value.trim());
  if (seconds != null) return Duration(seconds: max(seconds, 0));
  try {
    final wait = parseHttpDate(value).difference(DateTime.now());
    return wait.isNegative ? Duration.zero : wait;
  } catch (_) {
    return null;
  }
}

/// Opens an event stream at [url] and gives its events; see
/// [SseClient.connect], which this calls on a client made for the one
/// stream.
///
/// Give [client] to reuse an [http.Client], for example one with your own
/// settings or a fake in tests; otherwise one is made for the stream and
/// closed with it. On the web the default client streams through `fetch`.
Stream<SseEvent> connectSse(
  Uri url, {
  String method = 'GET',
  Map<String, String>? headers,
  Object? body,
  http.Client? client,
  SseReconnect? reconnect,
  String? lastEventId,
  Duration? connectTimeout,
  Duration? idleTimeout,
  int? maxEventSize,
  void Function(SseStatus status)? onStatus,
  void Function(String line)? onLine,
}) {
  final sse = SseClient(
    client: client,
    connectTimeout: connectTimeout,
    idleTimeout: idleTimeout,
    maxEventSize: maxEventSize,
    onLine: onLine,
  );
  final events = sse.connect(
    url,
    method: method,
    headers: headers,
    body: body,
    reconnect: reconnect,
    lastEventId: lastEventId,
    onStatus: onStatus,
  );
  // the client made here lives as long as the stream
  return _closing(events, sse.close);
}

Stream<T> _closing<T>(Stream<T> stream, void Function() onEnd) {
  late final StreamController<T> out;
  StreamSubscription<T>? inner;
  out = StreamController<T>(
    sync: true,
    onListen: () {
      inner = stream.listen(
        out.add,
        onError: out.addError,
        onDone: () {
          onEnd();
          out.close();
        },
      );
    },
    onPause: () => inner?.pause(),
    onResume: () => inner?.resume(),
    onCancel: () async {
      await inner?.cancel();
      onEnd();
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

/// Helpers for event streams, and for the streams of AI APIs.
extension SseEventStream on Stream<SseEvent> {
  /// The events up to, not including, a `[DONE]` event; the stream (and
  /// the request) ends there.
  Stream<SseEvent> untilDone() => takeWhile((event) => !event.isDone);

  /// The `data` of each event up to `[DONE]`, decoded as JSON.
  Stream<Object?> json() => untilDone().map((event) => event.json);

  /// Only the events of the given [type], such as `content_block_delta`.
  Stream<SseEvent> ofType(String type) => where((event) => event.event == type);

  /// The text of an OpenAI or OpenAI-compatible stream: Chat Completions
  /// (`choices[0].delta.content`) or the Responses API
  /// (`response.output_text.delta`). An error event ends it with an
  /// [SseException].
  Stream<String> openAIText() => json().expand((json) {
    if (json is! Map) return const <String>[];
    final error = json['error'];
    if (error != null) throw SseException(_message(error));
    final type = json['type'];
    if (type == 'response.output_text.delta') {
      final delta = json['delta'];
      return delta is String && delta.isNotEmpty ? [delta] : const <String>[];
    }
    if (type == 'response.failed' || type == 'error') {
      throw SseException(_message(json['response'] ?? json));
    }
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) return const <String>[];
    final choice = choices.first;
    final delta = choice is Map ? choice['delta'] : null;
    final content = delta is Map ? delta['content'] : null;
    return content is String && content.isNotEmpty
        ? [content]
        : const <String>[];
  });

  /// The text of an Anthropic Messages stream (`text_delta`s), ending at
  /// `message_stop`. An `error` event ends it with an [SseException].
  Stream<String> anthropicText() =>
      takeWhile((event) => event.event != 'message_stop').expand((event) {
        if (event.event == 'error') {
          final json = event.json;
          throw SseException(
            _message(json is Map ? json['error'] ?? json : json),
          );
        }
        if (event.event != 'content_block_delta') return const <String>[];
        final json = event.json;
        final delta = json is Map ? json['delta'] : null;
        if (delta is! Map || delta['type'] != 'text_delta') {
          return const <String>[];
        }
        final text = delta['text'];
        return text is String && text.isNotEmpty ? [text] : const <String>[];
      });

  /// The text of a Gemini `streamGenerateContent?alt=sse` stream, thought
  /// parts left out. A blocked prompt or an error ends it with an
  /// [SseException].
  Stream<String> geminiText() => json().expand((json) {
    if (json is! Map) return const <String>[];
    final error = json['error'];
    if (error != null) throw SseException(_message(error));
    final feedback = json['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw SseException('Blocked: ${feedback['blockReason']}');
    }
    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty) return const <String>[];
    final candidate = candidates.first;
    final content = candidate is Map ? candidate['content'] : null;
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) return const <String>[];
    return [
      for (final part in parts)
        if (part is Map && part['thought'] != true && part['text'] is String)
          part['text'] as String,
    ].where((text) => text.isNotEmpty);
  });
}

String _message(Object? error) {
  if (error is Map) {
    final message = error['message'] ?? error['error'];
    if (message != null) return _message(message);
  }
  return '$error';
}
