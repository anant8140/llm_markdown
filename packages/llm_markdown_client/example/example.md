# Example

```dart
import 'package:flutter/material.dart';
import 'package:llm_client/llm_client.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_client/llm_markdown_client.dart';

class Answer extends StatefulWidget {
  const Answer({super.key, required this.provider, required this.prompt});
  final LlmProvider provider;
  final String prompt;

  @override
  State<Answer> createState() => _AnswerState();
}

class _AnswerState extends State<Answer> {
  final _controller = StreamingMarkdownController();

  @override
  void initState() {
    super.initState();
    _controller
        .addLlmEvents(
          widget.provider.stream(
            LlmRequest(
              model: 'gpt-4.1-mini',
              messages: [LlmMessage.user(widget.prompt)],
            ),
          ),
        )
        // an error is shown in the reply itself
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: StreamingMarkdown(controller: _controller)),
      TextButton(onPressed: _controller.complete, child: const Text('Stop')),
    ],
  );
}
```
