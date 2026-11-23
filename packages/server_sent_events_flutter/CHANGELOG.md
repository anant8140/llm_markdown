## 0.1.0

* `SseBuilder`: builds from an event stream and its connection status,
  opens the stream once, restarts with `restartKey`, and closes the
  connection when removed.
* `SseStatusNotifier`: the status of a connection made elsewhere.
