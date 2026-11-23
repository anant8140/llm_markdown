import 'dart:async';

import 'event.dart';

/// Writes [event] in the event stream format, for a server: `event:`
/// unless it is `message`, `id:`, `retry:`, one `data:` line per line of
/// its data, and a blank line.
///
/// Throws an [ArgumentError] when the type or ID has a line break, which
/// the format can't carry.
String encodeSseEvent(SseEvent event) {
  final out = StringBuffer();
  if (event.event != 'message') {
    _single(event.event, 'event');
    out.write('event: ${event.event}\n');
  }
  final id = event.id;
  if (id != null) {
    _single(id, 'id');
    if (id.contains('\u0000')) {
      throw ArgumentError.value(id, 'id', 'contains NUL');
    }
    out.write('id: $id\n');
  }
  final retry = event.retry;
  if (retry != null) out.write('retry: ${retry.inMilliseconds}\n');
  for (final line in event.data.split(RegExp('\r\n|\r|\n'))) {
    out.write('data: $line\n');
  }
  out.write('\n');
  return out.toString();
}

/// A comment line, which clients ignore; servers send them as keep-alives
/// so proxies don't close a quiet connection.
String encodeSseComment([String text = '']) {
  _single(text, 'text');
  return ':${text.isEmpty ? '' : ' $text'}\n\n';
}

void _single(String value, String name) {
  if (value.contains('\n') || value.contains('\r')) {
    throw ArgumentError.value(value, name, 'contains a line break');
  }
}

/// Turns events into event stream text, for a server written in Dart
/// (`dart:io`, shelf, dart_frog); encode it with `utf8` and write it to the
/// response, with the content type `text/event-stream`.
class SseEncoder extends StreamTransformerBase<SseEvent, String> {
  /// An encoder that sends a comment as a keep-alive after every
  /// [keepAlive] without an event, when given.
  const SseEncoder({this.keepAlive});

  /// How long the stream may be quiet before a keep-alive is sent.
  final Duration? keepAlive;

  @override
  Stream<String> bind(Stream<SseEvent> stream) {
    final encoded = stream.map(encodeSseEvent);
    final every = keepAlive;
    if (every == null) return encoded;
    late final StreamController<String> out;
    StreamSubscription<String>? inner;
    Timer? timer;
    void schedule() {
      timer?.cancel();
      timer = Timer(every, () {
        out.add(encodeSseComment());
        schedule();
      });
    }

    out = StreamController<String>(
      onListen: () {
        schedule();
        inner = encoded.listen(
          (text) {
            out.add(text);
            schedule();
          },
          onError: out.addError,
          onDone: () {
            timer?.cancel();
            out.close();
          },
        );
      },
      onPause: () => inner?.pause(),
      onResume: () => inner?.resume(),
      onCancel: () {
        timer?.cancel();
        return inner?.cancel();
      },
    );
    return out.stream;
  }
}
