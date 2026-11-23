## 0.1.1

* A shorter package description, so search results show all of it.

## 0.1.0

* `connectSse`: any method, headers and body; `SseException` with the status
  and body of a failed request; cancel aborts the request; reconnects with
  `Last-Event-ID` and the server's `retry:`; works on the web.
* `SseDecoder`, a byte stream to events, following the HTML standard.
* `untilDone()` and `json()` for OpenAI-style streams.
