# llm_markdown_chat

A ready AI chat screen for Flutter, on top of
[llm_markdown](https://pub.dev/packages/llm_markdown): replies stream in as
Markdown without flicker, with code, tables, math and diagrams.

- Message list that keeps the newest reply in view while it grows
- Input box that grows with the text; Enter sends, Shift+Enter adds a line
- Send button that turns into stop while a reply is written
- Copy and "Try again" under the replies
- Suggestions while the chat is empty
- Errors shown in the reply, with the text so far kept
- Plain widgets: fits Material, Cupertino or your own design, follows the
  app's text style and accent color
- Works with any model: you write the reply into a controller, for example
  with the OpenAI, Anthropic, Gemini, Ollama or Firebase AI adapters of
  `llm_markdown`

**[Try it in the browser](https://anant8140.github.io/llm_markdown/chat/)**
(a pretend model, no key needed)

<img src="https://raw.githubusercontent.com/anant8140/llm_markdown/main/packages/llm_markdown_chat/doc/chat.gif" width="320" alt="A reply streaming into the chat">

## Usage

```dart
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_chat/llm_markdown_chat.dart';

final chat = LlmChatController(
  onReply: (prompt, reply, history) async {
    final request = http.Request('POST', Uri.parse(url))
      ..headers.addAll(headers)
      ..body = jsonEncode({
        'model': 'gpt-4.1-mini',
        'stream': true,
        'messages': [
          for (final message in history)
            {'role': message.role.name, 'content': message.text},
          {'role': 'user', 'content': prompt},
        ],
      });
    final response = await client.send(request);
    await reply.addOpenAIStream(response.stream);
  },
);

// in the widget tree:
LlmChatView(
  controller: chat,
  suggestions: const ['What can you do?'],
)
```

`onReply` gets the prompt, the reply's `StreamingMarkdownController` and
the chat before the prompt. Any stream of text works too:
`await reply.addStream(myStream)`. When `onReply` ends the reply is
completed; an error ends it with that error.

The stop button calls `chat.stop()`, which completes the reply; the
adapters and `addStream` then cancel the response, which closes the
request.

## Saved chats

```dart
LlmChatController(
  onReply: askModel,
  history: [
    ChatMessage.user('Hi'),
    ChatMessage.assistant('Hello! How can I help?'),
  ],
)
```

`chat.messages` gives them back to save, each with its `role` and `text`.

## Customizing

| Option | What it does |
| --- | --- |
| `style` | colors, radius, padding; defaults to `LlmChatStyle.of(context)` |
| `labels` | the words, for other languages |
| `emptyBuilder`, `suggestions` | what an empty chat shows |
| `userMessageBuilder` | your own bubble for the user's messages |
| `replyBuilder` | your own `StreamingMarkdown`, with any of its options |
| `onLinkTap` | links tapped in replies |

Also `chat.retry()`, `chat.clear()` and `chat.isReplying` for your own
buttons.

## License

MIT
