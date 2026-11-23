/// Flutter widgets for `package:server_sent_events`: [SseBuilder] follows
/// an event stream and its connection, and [SseStatusBuilder] only the
/// connection.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:server_sent_events/server_sent_events.dart';

export 'package:server_sent_events/server_sent_events.dart';

/// What [SseBuilder] has seen so far.
@immutable
class SseSnapshot<T> {
  /// A snapshot; see the fields.
  const SseSnapshot({
    required this.status,
    this.value,
    this.event,
    this.error,
    this.eventCount = 0,
  });

  /// The state of the connection.
  final SseStatus status;

  /// The value built from the events so far with `SseBuilder.reduce`, or
  /// the initial value.
  final T? value;

  /// The latest event, if one arrived.
  final SseEvent? event;

  /// The error that ended the stream, if it failed.
  final Object? error;

  /// How many events arrived.
  final int eventCount;

  /// Whether the stream failed.
  bool get hasError => error != null;

  /// Whether the stream is over, done or failed.
  bool get isClosed => status == SseStatus.closed;
}

/// Opens an event stream and rebuilds as events arrive and as the
/// connection opens, drops and closes.
///
/// ```dart
/// SseBuilder<String>(
///   connect: (onStatus) => connectSse(url, onStatus: onStatus),
///   initialValue: '',
///   reduce: (text, event) => text + event.data,
///   builder: (context, snapshot) => Text(snapshot.value!),
/// )
/// ```
///
/// The stream is opened once, when the widget is first built, and again
/// only when [restartKey] changes. Removing the widget cancels it, which
/// closes the connection.
class SseBuilder<T> extends StatefulWidget {
  /// A builder for the stream [connect] opens.
  const SseBuilder({
    super.key,
    required this.connect,
    required this.builder,
    this.reduce,
    this.initialValue,
    this.restartKey,
    this.onEvent,
    this.onError,
    this.onDone,
  });

  /// Opens the stream. Pass `onStatus` on to `connectSse` or
  /// `SseClient.connect` so the snapshot's status follows the connection;
  /// without it the status is `open` from the first event.
  final Stream<SseEvent> Function(void Function(SseStatus status) onStatus)
  connect;

  /// Builds from what was seen so far.
  final Widget Function(BuildContext context, SseSnapshot<T> snapshot) builder;

  /// Folds each event into the value: for a chat reply, add the text; for
  /// a feed, add to a list. Without it the value stays [initialValue].
  final T Function(T? value, SseEvent event)? reduce;

  /// The value before the first event.
  final T? initialValue;

  /// When this changes, the stream is closed and opened again from the
  /// start, for example with a new question.
  final Object? restartKey;

  /// Called with each event, after the value is updated.
  final void Function(SseEvent event)? onEvent;

  /// Called when the stream fails.
  final void Function(Object error)? onError;

  /// Called when the stream ends without an error.
  final VoidCallback? onDone;

  @override
  State<SseBuilder<T>> createState() => _SseBuilderState<T>();
}

class _SseBuilderState<T> extends State<SseBuilder<T>> {
  StreamSubscription<SseEvent>? _subscription;
  late SseSnapshot<T> _snapshot;
  // which run of the stream callbacks belong to; older ones are ignored
  var _run = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(SseBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.restartKey != oldWidget.restartKey) {
      _stop();
      _start();
    }
  }

  void _set(SseSnapshot<T> next) {
    if (!mounted) return;
    setState(() => _snapshot = next);
  }

  SseSnapshot<T> _with({SseStatus? status, Object? error}) => SseSnapshot<T>(
    status: status ?? _snapshot.status,
    value: _snapshot.value,
    event: _snapshot.event,
    error: error ?? _snapshot.error,
    eventCount: _snapshot.eventCount,
  );

  void _start() {
    final run = ++_run;
    _snapshot = SseSnapshot<T>(
      status: SseStatus.connecting,
      value: widget.initialValue,
    );
    final stream = widget.connect((status) {
      if (run != _run || status == _snapshot.status) return;
      // a status can come while the widget is building (the first one
      // does): show it after this frame
      scheduleMicrotask(() {
        if (run == _run) _set(_with(status: status));
      });
    });
    _subscription = stream.listen(
      (event) {
        if (run != _run) return;
        final reduce = widget.reduce;
        _set(
          SseSnapshot<T>(
            status: _snapshot.status == SseStatus.connecting
                ? SseStatus.open
                : _snapshot.status,
            value: reduce == null
                ? _snapshot.value
                : reduce(_snapshot.value, event),
            event: event,
            eventCount: _snapshot.eventCount + 1,
          ),
        );
        widget.onEvent?.call(event);
      },
      onError: (Object error) {
        if (run != _run) return;
        _set(_with(status: SseStatus.closed, error: error));
        widget.onError?.call(error);
      },
      onDone: () {
        if (run != _run) return;
        _set(_with(status: SseStatus.closed));
        if (!_snapshot.hasError) widget.onDone?.call();
      },
    );
  }

  void _stop() {
    _run++;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
}

/// Follows the status of a connection made elsewhere: give its
/// [SseStatusNotifier.call] as `onStatus` to `connectSse`, and build from
/// the notifier with a `ValueListenableBuilder`, for a "Reconnecting…"
/// line.
class SseStatusNotifier extends ValueNotifier<SseStatus?> {
  /// A notifier with no status yet.
  SseStatusNotifier() : super(null);

  /// Sets the status; pass this as `onStatus`.
  void call(SseStatus status) => value = status;
}
