# Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:llm_client/llm_client.dart' as llm;
import 'package:llm_client_ai_toolkit/llm_client_ai_toolkit.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chat')),
    body: LlmChatView(
      provider: LlmClientProvider(
        // a local model, no key needed
        client: llm.OllamaProvider(),
        model: 'llama3.2',
      ),
    ),
  );
}
```
