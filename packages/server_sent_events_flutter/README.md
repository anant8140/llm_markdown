# server_sent_events_flutter

Flutter widgets for [server_sent_events](https://pub.dev/packages/server_sent_events).

`SseBuilder` opens an event stream, rebuilds as events arrive and as the
connection opens, drops and closes, and closes the connection when the
widget is removed.

```dart
import 'package:server_sent_events_flutter/server_sent_events_flutter.dart';

SseBuilder<String>(
  connect: (onStatus) => connectSse(
    Uri.parse('https://example.com/reply'),
    method: 'POST',
    body: {'question': question},
    onStatus: onStatus,
  ),
  restartKey: question,            // a new question starts a new stream
  initialValue: '',
  reduce: (text, event) => text! + event.data,
  builder: (context, snapshot) {
    if (snapshot.hasError) return Text('Failed: ${snapshot.error}');
    return Column(children: [
      Text(snapshot.value!),
      if (snapshot.status == SseStatus.reconnecting)
        const Text('Reconnecting…'),
    ]);
  },
)
```

- The stream is opened once, not on every rebuild, and again only when
  `restartKey` changes.
- `reduce` folds each event into the value you build from: add text for a
  reply, add to a list for a feed.
- `snapshot` has `status`, `value`, the latest `event`, `error` and
  `eventCount`.
- `onEvent`, `onError` and `onDone` are called as things happen.

For a connection made elsewhere, `SseStatusNotifier` follows its status:

```dart
final status = SseStatusNotifier();
final events = connectSse(url, onStatus: status.call);
// ValueListenableBuilder(valueListenable: status, ...)
```

The package exports `server_sent_events`, so one import is enough.

## License

MIT
