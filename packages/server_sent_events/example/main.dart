import 'dart:io';

import 'package:server_sent_events/server_sent_events.dart';

/// Streams a reply from an OpenAI-compatible API:
/// `OPENAI_API_KEY=... dart run example/main.dart`
Future<void> main() async {
  final events = connectSse(
    Uri.parse('https://api.openai.com/v1/chat/completions'),
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ${Platform.environment['OPENAI_API_KEY']}',
    },
    body: {
      'model': 'gpt-4.1-mini',
      'stream': true,
      'messages': [
        {'role': 'user', 'content': 'Say hello in three languages.'},
      ],
    },
  );
  try {
    await for (final json in events.json()) {
      final choices = (json! as Map)['choices'] as List;
      if (choices.isEmpty) continue;
      final text = (choices.first as Map)['delta']?['content'];
      if (text is String) stdout.write(text);
    }
    stdout.writeln();
  } on SseException catch (error) {
    stderr.writeln('${error.statusCode}: ${error.body}');
  }
}
