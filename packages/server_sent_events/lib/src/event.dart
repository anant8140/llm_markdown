import 'dart:convert';

/// One server-sent event.
class SseEvent {
  /// An event with [data], of type [event].
  const SseEvent(this.data, {this.event = 'message', this.id, this.retry});

  /// The event type, from the `event:` field; `message` when there is none.
  final String event;

  /// The data, the `data:` lines joined with newlines.
  final String data;

  /// The last event ID the server set, from this or an earlier event, or
  /// null when it set none. Sent back as `Last-Event-ID` on a reconnect.
  final String? id;

  /// The reconnection time the server asked for with this event's `retry:`
  /// field, if any.
  final Duration? retry;

  /// [data] decoded as JSON.
  ///
  /// Throws a [FormatException] when it isn't JSON.
  Object? get json => jsonDecode(data);

  /// Whether [data] is `[DONE]`, the last event of an OpenAI-style stream.
  bool get isDone => data.trim() == '[DONE]';

  @override
  bool operator ==(Object other) =>
      other is SseEvent &&
      other.event == event &&
      other.data == data &&
      other.id == id &&
      other.retry == retry;

  @override
  int get hashCode => Object.hash(event, data, id, retry);

  @override
  String toString() =>
      'SseEvent(${event == 'message' ? '' : '$event: '}$data'
      '${id == null ? '' : ', id: $id'}'
      '${retry == null ? '' : ', retry: ${retry!.inMilliseconds} ms'})';
}

/// A failed SSE request: the server answered with an error status or with
/// something that isn't an event stream.
class SseException implements Exception {
  /// An error with [message].
  const SseException(this.message, {this.statusCode, this.body});

  /// What went wrong.
  final String message;

  /// The HTTP status of the response, if there was one.
  final int? statusCode;

  /// The start of the response body, such as the JSON error an AI API
  /// sends with a 4xx status.
  final String? body;

  @override
  String toString() =>
      'SseException: $message'
      '${body == null || body!.isEmpty ? '' : '\n$body'}';
}
