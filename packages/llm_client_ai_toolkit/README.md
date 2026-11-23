# llm_client_ai_toolkit

Use OpenAI, Anthropic, Gemini and Ollama in the
[Flutter AI Toolkit](https://pub.dev/packages/flutter_ai_toolkit)'s
`LlmChatView`. The toolkit ships a provider for Firebase AI; this package
adds one backed by [llm_client](https://pub.dev/packages/llm_client), so
the same chat view talks to other models.

```dart
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:llm_client/llm_client.dart' as llm;
import 'package:llm_client_ai_toolkit/llm_client_ai_toolkit.dart';

LlmChatView(
  provider: LlmClientProvider(
    client: llm.OpenAIProvider(apiKey: apiKey),
    // or llm.AnthropicProvider, llm.GeminiProvider, llm.OllamaProvider
    model: 'gpt-4.1-mini',
    system: 'You are a helpful assistant.',
  ),
)
```

`llm_client` is imported with a prefix because both packages have a class
named `LlmProvider`.

- The chat's history is sent with every prompt, and kept in `history`,
  which you can save and set again.
- The toolkit's stop button aborts the request.
- An error from the API shows in the chat with the API's own message.
- A link attachment is added to the prompt as its URL. Files and images
  are not sent, since `llm_client` sends text only:
  `onUnsupportedAttachment` is told about each, and
  `failOnUnsupportedAttachment: true` fails the reply instead.

To show the replies with [llm_markdown](https://pub.dev/packages/llm_markdown)
instead of the toolkit's own Markdown:

```dart
LlmChatView(
  provider: provider,
  responseBuilder: (context, response) => StreamingMarkdown.text(
    response,
    completeAfter: const Duration(seconds: 1),
  ),
)
```

Do not put an API key in an app you ship; call your own server, which
keeps the key, through `OpenAIProvider(baseUrl: ...)`.

## License

MIT
