## 0.2.1

* A request that can't be built, such as a `body` that isn't JSON, ends the
  stream with the error instead of leaving it waiting forever.

## 0.2.0

* `SseClient`: a base URL, headers built for each request (async, so a
  token can be fetched), and `onUnauthorized` to refresh a token after a
  401 and try once more.
* `onStatus`: connecting, open, reconnecting, closed.
* `connectTimeout` and `idleTimeout`, for servers that don't answer and
  connections that went quiet.
* `Retry-After` on 429 and 503 is waited for; reconnect waits get
  `jitter`.
* `maxEventSize`, so a broken server can't fill the memory.
* `onLine` sees every line, for logging.
* `ofType`, and `openAIText`, `anthropicText` and `geminiText` for the text
  of AI streams.
* `SseEncoder`, `encodeSseEvent` and `encodeSseComment` for servers written
  in Dart, with keep-alives.
* `package:server_sent_events/testing.dart`: `FakeSseClient` for tests.
* A shorter package description.

## 0.1.0

* `connectSse`: any method, headers and body; `SseException` with the status
  and body of a failed request; cancel aborts the request; reconnects with
  `Last-Event-ID` and the server's `retry:`; works on the web.
* `SseDecoder`, a byte stream to events, following the HTML standard.
* `untilDone()` and `json()` for OpenAI-style streams.
