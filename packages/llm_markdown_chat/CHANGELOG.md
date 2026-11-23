## 0.1.0

* `LlmChatController`: messages, `send`, `stop`, `retry`, `clear`, and an
  `onReply` callback that writes each reply into a
  `StreamingMarkdownController`.
* `LlmChatView`: message list, streaming Markdown replies, input box with
  send and stop, copy and try again, suggestions, and a style that follows
  the app.
* The `history` given to `onReply` leaves out turns whose reply failed or
  wrote nothing, so it can go to a model as it is.
* Enter that picks an input method candidate, and a held Enter, don't send
  twice or add new lines.
