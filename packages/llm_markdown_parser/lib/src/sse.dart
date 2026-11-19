import 'dart:async';
import 'dart:convert';

/// One event of a server-sent events (SSE) stream.
class ServerSentEvent {
  /// Creates an event.
  const ServerSentEvent(this.data, {this.event});

  /// The `event:` field, or null for the default "message" event.
  final String? event;

  /// The `data:` lines, joined with newlines.
  final String data;
}

/// Splits the raw bytes of an HTTP response body into server-sent events.
///
/// Works with any HTTP client that exposes the body as a byte stream, e.g.
/// `StreamedResponse.stream` from `package:http`.
Stream<ServerSentEvent> serverSentEvents(Stream<List<int>> bytes) async* {
  String? event;
  final data = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield ServerSentEvent(data.join('\n'), event: event);
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') event = value;
    if (field == 'data') data.add(value);
  }
  if (data.isNotEmpty) yield ServerSentEvent(data.join('\n'), event: event);
}

/// Error from a model API, sent inside its event stream.
class ModelStreamError implements Exception {
  /// Creates an error with the API's [message].
  const ModelStreamError(this.message);

  /// What the API reported.
  final String message;

  @override
  String toString() => 'ModelStreamError: $message';
}
