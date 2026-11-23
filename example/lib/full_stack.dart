// The whole path of an AI reply, with the packages of this repository:
//
//   llm_client          asks the model (OpenAI, Anthropic, Gemini, Ollama)
//   server_sent_events  reads the stream of the reply (inside llm_client)
//   partial_json        reads tool arguments while they are written
//   llm_markdown        shows the reply
//   llm_markdown_client joins the two: controller.addLlmEvents(...)
//
// Run it: flutter run -t lib/full_stack.dart
// It answers from a fake server, so it needs no API key; give
// [FullStackDemo] a real provider to talk to a model.
import 'dart:convert';

import 'package:llm_client/llm_client.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_client/llm_markdown_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:server_sent_events/server_sent_events.dart';
import 'package:server_sent_events/testing.dart';

void main() =>
    runApp(MaterialApp(home: FullStackDemo(provider: fakeProvider())));

/// A chat with one question box; the reply streams into `llm_markdown`.
class FullStackDemo extends StatefulWidget {
  const FullStackDemo({super.key, required this.provider, this.model = 'demo'});

  final LlmProvider provider;
  final String model;

  @override
  State<FullStackDemo> createState() => _FullStackDemoState();
}

class _FullStackDemoState extends State<FullStackDemo> {
  final _controller = StreamingMarkdownController();
  final _question = TextEditingController(
    text: 'What is the weather in Paris?',
  );
  var _busy = false;

  Future<void> _ask() async {
    _controller.reset();
    setState(() => _busy = true);
    try {
      await _controller.addLlmEvents(
        widget.provider.stream(
          LlmRequest(
            model: widget.model,
            messages: [LlmMessage.user(_question.text)],
            tools: const [
              LlmTool(
                name: 'get_weather',
                description: 'The weather in a city',
                parameters: {
                  'type': 'object',
                  'properties': {
                    'city': {'type': 'string'},
                  },
                },
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // the error is shown in the reply
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('llm_client + llm_markdown')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: TextField(controller: _question)),
              const SizedBox(width: 8),
              _busy
                  ? TextButton(
                      // ends the reply; showReply then cancels the request
                      onPressed: _controller.complete,
                      child: const Text('Stop'),
                    )
                  : FilledButton(onPressed: _ask, child: const Text('Ask')),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: StreamingMarkdown(controller: _controller),
            ),
          ),
        ],
      ),
    ),
  );
}

/// An OpenAI-style provider answered by a fake server: a tool call whose
/// arguments arrive in pieces, then a Markdown reply.
OpenAIProvider fakeProvider({
  Duration delay = const Duration(milliseconds: 60),
  FakeSseClient? client,
}) => OpenAIProvider(
  apiKey: 'demo',
  client:
      client ??
      FakeSseClient(
        (request) => FakeSseResponse.events(demoEvents(), delay: delay),
      ),
);

/// The events of the demo reply, as the Chat Completions API sends them.
List<SseEvent> demoEvents() {
  SseEvent chunk(Map<String, Object?> delta, {String? finish}) => SseEvent(
    jsonEncode({
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': finish},
      ],
    }),
  );
  SseEvent arguments(String piece) => chunk({
    'tool_calls': [
      {
        'index': 0,
        'function': {'arguments': piece},
      },
    ],
  });
  const reply = [
    '## Paris today\n\n',
    'It is **18 °C** and ',
    'partly cloudy.\n\n',
    '| | |\n|---|---|\n',
    '| Wind | 12 km/h |\n',
    '| Rain | 10% |\n',
  ];
  return [
    chunk({
      'role': 'assistant',
      'tool_calls': [
        {
          'index': 0,
          'id': 'call_1',
          'type': 'function',
          'function': {'name': 'get_weather', 'arguments': ''},
        },
      ],
    }),
    arguments('{"city": "Pa'),
    arguments('ris, Fr'),
    arguments('ance"}'),
    for (final text in reply) chunk({'content': text}),
    chunk({}, finish: 'stop'),
    const SseEvent('[DONE]'),
  ];
}
