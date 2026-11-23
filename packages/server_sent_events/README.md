# server_sent_events

A server-sent events (SSE) client for Dart and Flutter, made for streaming
AI APIs and just as good for any event stream.

- **Any request:** `GET` or `POST`, your headers, a JSON or text body. A
  browser `EventSource` can only `GET`; AI APIs need a `POST`.
- **Errors you can show:** a 4xx or 5xx status, or JSON where an event
  stream was expected, ends the stream with an `SseException` holding the
  status and the body the API sent, such as `Invalid API key`.
- **Cancel closes the request:** cancelling the subscription aborts the
  HTTP request, so a stop button really stops the reply (and its cost).
- **Reconnects** like `EventSource`, with `Last-Event-ID`, the server's
  `retry:` time and growing waits; only `GET` by default, since sending a
  `POST` again would start a new AI reply.
- **Every platform:** Android, iOS, desktop and the web, where it streams
  through `fetch` instead of waiting for the whole response.
- **Follows the standard:** `\n`, `\r\n` and `\r` line ends, comments,
  multi-line data, the BOM, `id` and `retry` as the HTML standard reads
  them, UTF-8 split across chunks.

Pure Dart; its only dependency is `package:http`.

## Usage

```dart
import 'package:server_sent_events/server_sent_events.dart';

final events = connectSse(
  Uri.parse('https://api.openai.com/v1/chat/completions'),
  method: 'POST',
  headers: {'Authorization': 'Bearer $apiKey'},
  body: {
    'model': 'gpt-4.1-mini',
    'stream': true,
    'messages': [
      {'role': 'user', 'content': 'Hello'},
    ],
  },
);

await for (final json in events.json()) {
  // one decoded `data:` per event, up to `data: [DONE]`
  final delta = (json as Map)['choices'][0]['delta']['content'];
  if (delta != null) print(delta);
}
```

Each `SseEvent` has `event` (the type, `message` by default), `data`, `id`
and `retry`, plus `json` and `isDone`.

```dart
// a feed that should stay open, like a browser EventSource
final subscription = connectSse(
  Uri.parse('https://example.com/updates'),
  reconnect: SseReconnect.always,
).listen((event) => print('${event.event}: ${event.data}'));

// stop: aborts the request and closes the connection
await subscription.cancel();
```

Errors:

```dart
try {
  await for (final event in connectSse(url, method: 'POST', body: body)) {
    // ...
  }
} on SseException catch (error) {
  print('${error.statusCode}: ${error.body}');
}
```

### Options

| | default | |
| --- | --- | --- |
| `method` | `GET` | any HTTP method |
| `headers` | – | added to `Accept: text/event-stream` |
| `body` | – | a `String`, bytes, or a `Map`/`List` sent as JSON |
| `reconnect` | `GET`: `SseReconnect()`, others: `SseReconnect.none` | when to open the stream again |
| `client` | a new `http.Client` | your own client, for example a mock in tests |
| `lastEventId` | – | the ID to resume from |

`SseReconnect(maxAttempts: 5, delay: 1 s, maxDelay: 30 s, factor: 2,
onClose: false)` reconnects after a network error and after a 408, 429 or
5xx status, and with `onClose` also after the server ends the stream. An
event that arrives resets the count.

### Decoding bytes you already have

`SseDecoder` turns any byte stream into events:

```dart
final events = response.stream.transform(const SseDecoder());
```

## With llm_markdown

The replies are Markdown; [llm_markdown](https://pub.dev/packages/llm_markdown)
shows them as they stream in, unfinished syntax and all.

## License

MIT
