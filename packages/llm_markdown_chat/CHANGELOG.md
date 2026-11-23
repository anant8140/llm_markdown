## 0.2.0

* Message actions: thumbs up and down under replies with `onFeedback`;
  `showCopy`, `showRegenerate` and `copyPlainText`; `messageActionsBuilder`
  for your own. `LlmChatController.regenerate` asks again for a reply.
* Edit a user message: the "Edit" button puts the text back in the input,
  and sending replaces that message and everything after it
  (`LlmChatController.edit`, `showEdit`).
* `LlmChatController.toJson` and `LlmChatController.fromJson` save and
  restore a chat, with a `version` field; `ChatMessage` has `createdAt`,
  and `ChatMessage.assistant` takes `thinking`, `sources` and `error`.
* `welcome`: a widget for the empty chat, next to `suggestions`.
* Attachments and voice input as callbacks, without plugins:
  `onPickAttachment`, `attachmentBuilder`, `onVoiceInput`,
  `ChatAttachment`, `ChatMessage.attachments`, and
  `send(prompt, attachments: ...)`.
* Several chats: `ChatListController` and `ChatListView`.
* `LlmChatController.sse` and `SseChatBackend` connect a streaming endpoint
  through `server_sent_events`; the stop button aborts the request.
* A reply that ended with an error now shows the error's text under it
  (`chatErrorText`, `errorBuilder`, `LlmChatStyle.errorColor`).
* The ids of new messages now contain the start time, so they don't repeat
  the ids of a restored chat.

## 0.1.1

* Screenshots, an animation of a reply streaming in, and a
  [live demo](https://anant8140.github.io/llm_markdown/chat/).

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
