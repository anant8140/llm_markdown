// Runs llm_client against a local Ollama server, through Ollama's own API
// or, with --openai, through its OpenAI-compatible endpoint (which checks
// OpenAIProvider against a real server):
//   dart run tool/live_ollama.dart [--openai] [model]
import 'dart:async';

import 'package:llm_client/llm_client.dart';

const weather = LlmTool(
  name: 'get_weather',
  description: 'Get the current weather for a city.',
  parameters: {
    'type': 'object',
    'properties': {
      'city': {'type': 'string', 'description': 'The city name'},
    },
    'required': ['city'],
  },
);

var failed = 0;
void check(String name, bool ok, [Object? detail]) {
  if (!ok) failed++;
  print('${ok ? 'PASS' : 'FAIL'}  $name${detail == null ? '' : '  ($detail)'}');
}

Future<void> main(List<String> args) async {
  final openai = args.contains('--openai');
  final names = args.where((a) => a != '--openai');
  final model = names.isEmpty ? 'qwen3.6:27b' : names.first;
  final LlmProvider ollama = openai
      ? OpenAIProvider(apiKey: 'ollama', baseUrl: 'http://localhost:11434/v1')
      : OllamaProvider();
  print(
    'model: $model, through ${openai ? 'the OpenAI-compatible endpoint' : "Ollama's API"}',
  );

  // 1. plain text, streamed
  {
    final clock = Stopwatch()..start();
    final events = await ollama
        .stream(
          LlmRequest(
            model: model,
            messages: [
              LlmMessage.system('Answer in one short sentence.'),
              LlmMessage.user('What is the capital of France?'),
            ],
            extra: const {'think': false},
          ),
        )
        .toList()
        .timeout(const Duration(minutes: 4));
    final text = events.whereType<LlmTextDelta>().map((e) => e.text).join();
    final done = events.whereType<LlmDone>().toList();
    final usage = events.whereType<LlmUsage>().toList();
    print('   text: ${text.trim()}  [${clock.elapsed.inSeconds}s]');
    check('text mentions Paris', text.contains('Paris'));
    check(
      'text came in several deltas',
      events.whereType<LlmTextDelta>().length > 1,
      events.whereType<LlmTextDelta>().length,
    );
    check(
      'one LlmDone, finish stop',
      done.length == 1 && done.single.finishReason == LlmFinishReason.stop,
      done.map((d) => '${d.finishReason}/${d.rawFinishReason}'),
    );
    check(
      'usage with token counts',
      usage.length == 1 &&
          (usage.single.inputTokens ?? 0) > 0 &&
          (usage.single.outputTokens ?? 0) > 0,
      usage.map((u) => '${u.inputTokens}/${u.outputTokens}'),
    );
    check('LlmDone is the last event', events.last is LlmDone);
  }

  // 2. thinking
  {
    final events = await ollama
        .stream(
          LlmRequest(
            model: model,
            messages: [
              LlmMessage.user(
                'What is 17 * 23? Think, then answer with the number.',
              ),
            ],
            extra: const {'think': true},
          ),
        )
        .toList()
        .timeout(const Duration(minutes: 4));
    final thinking = events
        .whereType<LlmThinkingDelta>()
        .map((e) => e.text)
        .join();
    final text = events.whereType<LlmTextDelta>().map((e) => e.text).join();
    print(
      '   thinking: ${thinking.length} chars; text: ${text.trim().replaceAll('\n', ' ')}',
    );
    check('thinking deltas arrive', thinking.isNotEmpty);
    check('answer has 391', text.contains('391'));
    check(
      'thinking is not in the text',
      thinking.isEmpty || !text.contains(thinking),
    );
  }

  // 3. tool call, then the round trip with the tool's result
  {
    final messages = [
      LlmMessage.user('What is the weather in Paris right now? Use the tool.'),
    ];
    final first = await ollama
        .complete(
          LlmRequest(
            model: model,
            messages: messages,
            tools: const [weather],
            extra: const {'think': false},
          ),
        )
        .timeout(const Duration(minutes: 4));
    print(
      '   tool calls: ${first.toolCalls.map((c) => '${c.name}(${c.arguments}) id=${c.id}')}  finish=${first.finishReason}',
    );
    check(
      'the model called get_weather',
      first.toolCalls.length == 1 &&
          first.toolCalls.single.name == 'get_weather',
    );
    check(
      'arguments are a map with the city',
      first.toolCalls.isNotEmpty &&
          '${first.toolCalls.first.arguments['city']}'.toLowerCase().contains(
            'paris',
          ),
    );
    check(
      'finish reason is toolCalls',
      first.finishReason == LlmFinishReason.toolCalls,
      first.rawFinishReason,
    );
    if (first.toolCalls.isNotEmpty) {
      final call = first.toolCalls.first;
      final second = await ollama
          .complete(
            LlmRequest(
              model: model,
              messages: [
                ...messages,
                first.message,
                LlmMessage.tool(
                  toolCallId: call.id,
                  toolName: call.name,
                  text: '{"temperature_c": 18, "sky": "partly cloudy"}',
                ),
              ],
              tools: const [weather],
              extra: const {'think': false},
            ),
          )
          .timeout(const Duration(minutes: 4));
      print(
        '   after the tool result: ${second.text.trim().replaceAll('\n', ' ')}',
      );
      check('the reply uses the tool result', second.text.contains('18'));
      check('no second tool call', second.toolCalls.isEmpty);
    }
  }

  // 4. events of a streamed tool call
  {
    final events = await ollama
        .stream(
          LlmRequest(
            model: model,
            messages: [LlmMessage.user('Weather in Tokyo? Use the tool.')],
            tools: const [weather],
            extra: const {'think': false},
          ),
        )
        .toList()
        .timeout(const Duration(minutes: 4));
    final kinds = events
        .map((e) => e.runtimeType.toString())
        .where((k) => k.contains('ToolCall'))
        .toList();
    check(
      'start, delta, done in order',
      kinds.join(',') == 'LlmToolCallStart,LlmToolCallDelta,LlmToolCallDone',
      kinds,
    );
  }

  // 5. cancel in the middle
  {
    final clock = Stopwatch()..start();
    final first = await ollama
        .text(
          LlmRequest(
            model: model,
            messages: [
              LlmMessage.user('Write a 600 word story about a lighthouse.'),
            ],
            extra: const {'think': false},
          ),
        )
        .first
        .timeout(const Duration(minutes: 4));
    final afterFirst = clock.elapsedMilliseconds;
    check(
      'cancel after the first piece returns at once',
      first.isNotEmpty,
      '${afterFirst}ms to first piece',
    );
    // the server stops generating: a short question answers quickly again
    final again = Stopwatch()..start();
    final text = await ollama
        .text(
          LlmRequest(
            model: model,
            messages: [LlmMessage.user('Say OK.')],
            extra: const {'think': false},
          ),
        )
        .join()
        .timeout(const Duration(minutes: 2));
    check(
      'the server is free again soon after',
      again.elapsed < const Duration(seconds: 20),
      '${again.elapsed.inSeconds}s, "${text.trim()}"',
    );
  }

  // 6. errors
  {
    Object? error;
    try {
      await ollama.complete(
        LlmRequest(
          model: 'no-such-model-xyz',
          messages: [LlmMessage.user('hi')],
        ),
      );
    } catch (e) {
      error = e;
    }
    print('   error: $error');
    check(
      'unknown model gives an LlmException with the status',
      error is LlmException && error.statusCode == 404,
      error is LlmException
          ? '${error.statusCode}: ${error.message}'
          : error.runtimeType,
    );
    Object? down;
    try {
      await OllamaProvider(baseUrl: 'http://127.0.0.1:9')
          .complete(LlmRequest(model: model, messages: [LlmMessage.user('hi')]))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      down = e;
    }
    check(
      'no server gives an error, not a hang',
      down != null,
      down.runtimeType,
    );
  }

  print(failed == 0 ? 'ALL PASSED' : '$failed FAILED');
}
