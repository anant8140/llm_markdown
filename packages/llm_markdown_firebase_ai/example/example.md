# Example

```dart
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_firebase_ai/llm_markdown_firebase_ai.dart';

class Answer extends StatefulWidget {
  const Answer({super.key, required this.prompt});
  final String prompt;

  @override
  State<Answer> createState() => _AnswerState();
}

class _AnswerState extends State<Answer> {
  final _controller = StreamingMarkdownController();

  @override
  void initState() {
    super.initState();
    final model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-2.5-flash',
    );
    _controller
        .addFirebaseAIStream(
          model.generateContentStream([Content.text(widget.prompt)]),
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
