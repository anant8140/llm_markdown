// Streams one reply from OpenAI and prints it.
//
//   OPENAI_API_KEY=sk-... dart run example/main.dart
import 'dart:io';

import 'package:llm_client/llm_client.dart';

Future<void> main() async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('Set OPENAI_API_KEY to run this example.');
    exitCode = 64;
    return;
  }

  // The other providers take the same request:
  //   AnthropicProvider(apiKey: ...), GeminiProvider(apiKey: ...),
  //   OllamaProvider()
  final provider = OpenAIProvider(apiKey: apiKey);
  const request = LlmRequest(
    model: 'gpt-4.1-mini',
    messages: [
      LlmMessage.system('Answer in one sentence.'),
      LlmMessage.user('Why is the sky blue?'),
    ],
  );

  try {
    await for (final event in provider.stream(request)) {
      switch (event) {
        case LlmTextDelta(:final text):
          stdout.write(text);
        case LlmUsage(:final inputTokens, :final outputTokens):
          stdout.writeln('\n[$inputTokens tokens in, $outputTokens out]');
        case LlmDone(:final finishReason):
          stdout.writeln('[finished: ${finishReason.name}]');
        default:
          break;
      }
    }
  } on LlmException catch (error) {
    stderr.writeln('${error.statusCode}: ${error.message}');
    exitCode = 1;
  }
}
