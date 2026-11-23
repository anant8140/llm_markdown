# llm_markdown_client

Streams [llm_client](https://pub.dev/packages/llm_client) replies into
[llm_markdown](https://pub.dev/packages/llm_markdown): one line from asking
a model (OpenAI, Anthropic, Gemini, Ollama) to showing its reply.

```dart
import 'package:llm_client/llm_client.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_client/llm_markdown_client.dart';

final provider = OpenAIProvider(apiKey: apiKey);
final controller = StreamingMarkdownController();

controller.reset();
await controller.addLlmEvents(
  provider.stream(
    LlmRequest(model: 'gpt-4.1-mini', messages: [LlmMessage.user(prompt)]),
  ),
);

// in the widget tree:
StreamingMarkdown(controller: controller)
```

- Text is appended as it arrives; thinking goes to the collapsible
  thinking section.
- Tool calls show as lines such as "Using get weather  Paris", with the
  arguments as the model writes them.
- An error from the API ends the reply and shows in it.
- `controller.complete()` (a stop button) or `reset()` cancels the stream,
  which aborts the request.
- `onEvent` sees every event, for token usage or the finished tool calls
  your app has to run.

## License

MIT
