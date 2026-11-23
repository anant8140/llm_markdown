# llm_markdown_firebase_ai

Streams [Firebase AI Logic](https://firebase.google.com/docs/ai-logic)
(`firebase_ai`) Gemini replies into
[llm_markdown](https://pub.dev/packages/llm_markdown), the Markdown widget
for AI chat replies that stream in.

- Text is appended as it arrives; unfinished syntax is closed before it is
  drawn.
- Thought summaries go to the collapsible thinking section.
- Function calls show as "Using web_search…" lines, with their arguments.
- Google Search grounding pages become the reply's sources.
- A blocked prompt or reply shows as an error, with the text so far kept.
- Calling `reset()` or `complete()` (a stop button) cancels the request at
  once.

<img src="https://raw.githubusercontent.com/anant8140/llm_markdown/main/packages/llm_markdown_firebase_ai/doc/firebase_ai.gif" width="320" alt="A Gemini reply with thinking, a search and sources">

The sources are in `controller.sources`; the app shows them its own way,
as the chips above.

Works with `firebase_ai` 3.15 and later, including the version
`flutter_ai_toolkit` uses.

## Usage

```dart
import 'package:firebase_ai/firebase_ai.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_firebase_ai/llm_markdown_firebase_ai.dart';

final model = FirebaseAI.googleAI().generativeModel(model: 'gemini-2.5-flash');
final controller = StreamingMarkdownController();

// in a chat:
final chat = model.startChat();
controller.reset();
await controller.addFirebaseAIStream(chat.sendMessageStream(Content.text(prompt)));

// in the widget tree:
StreamingMarkdown(controller: controller)
```

A stop button only needs `controller.complete()`.

If you use Google Search grounding, Google's terms ask you to show the
search suggestions it returns. `onSearchSuggestions` hands you their HTML,
to show in a web view under the reply:

```dart
controller.addFirebaseAIStream(
  stream,
  onSearchSuggestions: (html) => setState(() => _suggestionsHtml = html),
);
```

Code the model runs with the code execution tool, and its output, are added
to the reply as code blocks; `showCodeExecution: false` leaves them out.

## With the Flutter AI Toolkit

`LlmChatView` does the streaming itself and gives `responseBuilder` the text
so far. Show it with `llm_markdown`, no extra package needed:

```dart
LlmChatView(
  provider: FirebaseProvider(model: model),
  responseBuilder: (context, response) => StreamingMarkdown.text(
    response,
    completeAfter: const Duration(seconds: 1),
  ),
)
```

`completeAfter` counts a reply as done once it stops growing, since the
toolkit doesn't say when it ends.

## License

MIT
