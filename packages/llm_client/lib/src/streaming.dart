// What the providers share: running a wire decoder over a stream, reading
// errors, and putting streamed tool calls together.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:partial_json/partial_json.dart';
import 'package:server_sent_events/server_sent_events.dart';

import 'types.dart';

/// Gives an event to the listener.
typedef Emit = void Function(LlmEvent event);

/// Turns the chunks of one provider's stream into [LlmEvent]s.
abstract class WireDecoder<T> {
  /// Whether the reply is complete, so the connection can be closed.
  bool get isDone;

  /// Reads the next chunk. Throws an [LlmException] for an error chunk.
  void add(T chunk, Emit emit);

  /// Called when the connection closes without [isDone].
  void close(Emit emit) {
    throw const LlmException('The stream ended before the reply was finished');
  }
}

/// Runs [decoder] over the stream [open] gives. The stream is opened on
/// listen, cancelled on cancel and as soon as the decoder is done, and its
/// errors are passed through [mapError].
Stream<LlmEvent> decodeStream<T>({
  required Stream<T> Function() open,
  required WireDecoder<T> Function() decoder,
  Object Function(Object error)? mapError,
}) {
  late final StreamController<LlmEvent> out;
  StreamSubscription<T>? input;
  var closed = false;

  void finish([Object? error, StackTrace? stackTrace]) {
    if (closed) return;
    closed = true;
    final current = input;
    input = null;
    if (error != null) out.addError(error, stackTrace);
    unawaited(current?.cancel());
    unawaited(out.close());
  }

  void emit(LlmEvent event) {
    if (!closed) out.add(event);
  }

  out = StreamController<LlmEvent>(
    onListen: () {
      final wire = decoder();
      input = open().listen(
        (chunk) {
          if (closed) return;
          try {
            wire.add(chunk, emit);
          } catch (error, stackTrace) {
            finish(error, stackTrace);
            return;
          }
          if (wire.isDone) finish();
        },
        onError: (Object error, StackTrace stackTrace) {
          finish(mapError == null ? error : mapError(error), stackTrace);
        },
        onDone: () {
          try {
            if (!wire.isDone) wire.close(emit);
          } catch (error, stackTrace) {
            finish(error, stackTrace);
            return;
          }
          finish();
        },
      );
    },
    onPause: () => input?.pause(),
    onResume: () => input?.resume(),
    onCancel: () {
      closed = true;
      final current = input;
      input = null;
      return current?.cancel();
    },
  );
  return out.stream;
}

/// Opens an SSE stream with a JSON [body] and runs [decoder] over it.
Stream<LlmEvent> sseStream({
  required Uri url,
  required Map<String, String> headers,
  required Map<String, Object?> body,
  required http.Client? client,
  required WireDecoder<SseEvent> Function() decoder,
}) => decodeStream(
  open: () => connectSse(
    url,
    method: 'POST',
    headers: {'Content-Type': 'application/json', ...headers},
    body: jsonEncode(body),
    client: client,
    reconnect: SseReconnect.none,
  ),
  decoder: decoder,
  mapError: (error) => error is SseException
      ? apiError(error.statusCode, error.body, fallback: error.message)
      : error,
);

/// The lines of the response to a JSON POST, for APIs that stream JSON
/// Lines. Cancelling the subscription aborts the request. A status that is
/// not 2xx ends the stream with an [LlmException].
Stream<String> postLines({
  required Uri url,
  required Map<String, String> headers,
  required Map<String, Object?> body,
  required http.Client? client,
}) {
  final abort = Completer<void>();
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  late final StreamController<String> out;
  StreamSubscription<String>? lines;
  var cancelled = false;

  void end([Object? error, StackTrace? stackTrace]) {
    if (ownsClient) httpClient.close();
    if (cancelled) return;
    if (error != null) out.addError(error, stackTrace);
    unawaited(out.close());
  }

  out = StreamController<String>(
    onListen: () async {
      try {
        final request =
            http.AbortableRequest('POST', url, abortTrigger: abort.future)
              ..headers['Content-Type'] = 'application/json'
              ..headers.addAll(headers)
              ..body = jsonEncode(body);
        final response = await httpClient.send(request);
        if (cancelled) {
          unawaited(response.stream.listen(null).cancel());
          return;
        }
        final code = response.statusCode;
        if (code < 200 || code > 299) {
          final text = await utf8.decodeStream(response.stream);
          end(apiError(code, text, fallback: 'HTTP $code from $url'));
          return;
        }
        lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              out.add,
              onError: (Object error, StackTrace stackTrace) {
                if (!cancelled) out.addError(error, stackTrace);
              },
              onDone: end,
            );
        if (out.isPaused) lines!.pause();
      } catch (error, stackTrace) {
        end(error, stackTrace);
      }
    },
    onPause: () => lines?.pause(),
    onResume: () => lines?.resume(),
    onCancel: () async {
      cancelled = true;
      // closes the connection, also when the response has not started
      if (!abort.isCompleted) abort.complete();
      await lines?.cancel();
      if (ownsClient) httpClient.close();
    },
  );
  return out.stream;
}

/// An [LlmException] for an error response with [statusCode] and [body],
/// with the provider's message when the body is JSON that has one.
LlmException apiError(int? statusCode, String? body, {String? fallback}) {
  String? message;
  if (body != null) {
    try {
      message = errorMessage(jsonDecode(body));
    } on FormatException {
      // not JSON; the body is still given
    }
  }
  return LlmException(
    message ?? fallback ?? 'The request failed',
    statusCode: statusCode,
    body: body,
  );
}

/// The message of an error body: `{"error": {"message": "..."}}` (OpenAI,
/// Anthropic, Gemini), `{"error": "..."}` (Ollama), `{"message": "..."}`,
/// or a list holding one of these (Gemini without SSE).
String? errorMessage(Object? json) {
  if (json is List && json.isNotEmpty) return errorMessage(json.first);
  if (json is! Map) return null;
  final error = json['error'];
  if (error is String) return error;
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  final message = json['message'];
  return message is String ? message : null;
}

/// The JSON object in [data], the text of one event or line.
Map<String, Object?> decodeObject(String data) {
  Object? json;
  try {
    json = jsonDecode(data);
  } on FormatException {
    json = null;
  }
  if (json is Map<String, Object?>) return json;
  throw LlmException('Could not read the reply: not a JSON object', body: data);
}

/// Throws when [json] is an error the API sent in place of a chunk.
void throwIfError(Map<String, Object?> json, String data) {
  if (json['error'] == null) return;
  throw LlmException(
    errorMessage(json) ?? 'The provider reported an error',
    body: data,
  );
}

/// A copy of a JSON object that later changes to [value] leave alone.
Map<String, Object?> copyJsonObject(Object? value) => value is Map
    ? {for (final entry in value.entries) '${entry.key}': _copy(entry.value)}
    : {};

Object? _copy(Object? value) => switch (value) {
  Map() => copyJsonObject(value),
  List() => [for (final item in value) _copy(item)],
  _ => value,
};

/// Puts one streamed tool call together from the pieces of its arguments.
class ToolCallBuilder {
  /// A call [id] of the tool [name].
  ToolCallBuilder(this.id, this.name, {this.providerData = const {}});

  /// The ID of the call.
  final String id;

  /// The name of the tool.
  final String name;

  /// See [LlmToolCall.providerData].
  final Map<String, Object?> providerData;

  final _raw = StringBuffer();
  final _parser = PartialJsonParser(lenient: false);

  /// The event that starts the call.
  LlmToolCallStart start() => LlmToolCallStart(id, name);

  /// Adds the next [piece] of the arguments' JSON.
  LlmToolCallDelta add(String piece) {
    _raw.write(piece);
    try {
      _parser.add(piece);
    } on FormatException {
      throw _invalid();
    }
    return LlmToolCallDelta(
      id,
      _parser.hasValue ? copyJsonObject(_parser.value) : {},
      piece,
    );
  }

  /// Ends the call. A call with no arguments text has no arguments.
  LlmToolCallDone done() {
    final text = _raw.toString();
    Object? arguments = <String, Object?>{};
    if (text.trim().isNotEmpty) {
      try {
        arguments = jsonDecode(text);
      } on FormatException {
        throw _invalid();
      }
    }
    if (arguments is! Map<String, Object?>) throw _invalid();
    return LlmToolCallDone(
      LlmToolCall(
        id: id,
        name: name,
        arguments: arguments,
        providerData: providerData,
      ),
    );
  }

  LlmException _invalid() => LlmException(
    'The arguments of the tool call $name are not a JSON object',
    body: _raw.toString(),
  );
}

/// The events of a tool call that arrived whole, as Gemini and Ollama
/// send them.
void emitWholeToolCall(
  Emit emit, {
  required String id,
  required String name,
  required Object? arguments,
  Map<String, Object?> providerData = const {},
}) {
  final copy = copyJsonObject(arguments);
  emit(LlmToolCallStart(id, name));
  emit(LlmToolCallDelta(id, copy, jsonEncode(copy)));
  emit(
    LlmToolCallDone(
      LlmToolCall(
        id: id,
        name: name,
        arguments: copy,
        providerData: providerData,
      ),
    ),
  );
}

/// The name of the tool a tool message answers: its own, or the one in
/// the assistant message of [messages] that made the call.
String toolNameFor(LlmMessage message, List<LlmMessage> messages) =>
    message.toolName ?? callFor(message, messages)?.name ?? '';

/// The call a tool message answers, if an earlier message made it.
LlmToolCall? callFor(LlmMessage message, List<LlmMessage> messages) {
  for (final other in messages) {
    for (final call in other.toolCalls) {
      if (call.id == message.toolCallId) return call;
    }
  }
  return null;
}
