import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_chat/llm_markdown_chat.dart';

void main() => runApp(const ChatApp());

/// A chat with a pretend model, so it runs without an API key. Replace
/// [_pretendReply] with a real call, for example
/// `reply.addOpenAIStream(response.stream)`.
class ChatApp extends StatefulWidget {
  const ChatApp({super.key});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  late final _chat = LlmChatController(onReply: _pretendReply);

  Future<void> _pretendReply(
    String prompt,
    StreamingMarkdownController reply,
    List<ChatMessage> history,
  ) async {
    final answer =
        '## About "$prompt"\n\n'
        'This reply streams in **piece by piece**, like a real model. '
        'Unfinished syntax is closed before it is drawn.\n\n'
        '- It is message ${history.length ~/ 2 + 1} of this chat\n'
        '- Press the square to stop it\n\n'
        '```dart\nfinal chat = LlmChatController(onReply: askModel);\n```\n\n'
        '| Part | Done |\n| --- | --- |\n| Messages | yes |\n| Stop | yes |\n';
    await reply.addStream(_chunks(answer));
  }

  Stream<String> _chunks(String text) async* {
    for (var i = 0; i < text.length; i += 4) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      yield text.substring(i, i + 4 > text.length ? text.length : i + 4);
    }
  }

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: const Color(0xFF6750A4),
    title: 'llm_markdown_chat',
    builder: (context, _) => DefaultTextStyle(
      style: const TextStyle(
        fontSize: 15,
        height: 1.4,
        color: Color(0xFF1C1B1F),
      ),
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: LlmChatView(
                controller: _chat,
                autofocus: true,
                emptyBuilder: (context) => const Text(
                  'How can I help?',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                suggestions: const [
                  'Explain streams in Dart',
                  'Write a haiku',
                  'Plan a trip',
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
