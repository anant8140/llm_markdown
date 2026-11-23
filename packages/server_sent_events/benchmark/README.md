# Comparison with flutter_client_sse

The same scenarios run through `server_sent_events` and
`flutter_client_sse` 2.0.3 against one local server. Each row is what the
test saw, not a judgement; run it to check.

| scenario | server_sent_events | flutter_client_sse |
| --- | --- | --- |
| `data: hello` | `hello` | ` hello\n` (leading space and a line end kept) |
| two `data:` lines `a`, `b` | `a\nb` | ` a\n b\n` |
| the server ends the stream | the Dart stream ends | the Dart stream stays open |
| a 401 with a JSON error body | an `SseException` with status 401 and the body, 1 request | no error and no event; 3 requests in 12 s (it retries every 5 s) |
| an unknown field (`foo: bar`) before an event | ignored, as the standard says; 1 request | treated as an error: reconnects, 2 requests in 7 s, the event twice |
| cancelling the subscription | the connection closes | the connection stays open (it has a separate `unsubscribeFromSSE()`) |
| 50,000 events on one connection, 3 runs | 342, 278, 247 ms | 305, 273, 315 ms |

So the speed is the same; the difference is in what happens around the
events: errors, the end of the stream, cancelling and the exact data.

Measured on an Apple Silicon Mac, Flutter 3.50, `flutter test` (debug mode).

## Running it

```bash
cd benchmark
flutter pub get
flutter test test/compare_test.dart
```

Each scenario prints a `RESULT` line. It takes about a minute and a half,
most of it waiting to see whether the other package retries.
