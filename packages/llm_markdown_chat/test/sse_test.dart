import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown_chat/llm_markdown_chat.dart';
import 'package:server_sent_events/server_sent_events.dart';
import 'package:server_sent_events/testing.dart';

SseEvent _delta(String text) => SseEvent(
  jsonEncode({
    'choices': [
      {
        'delta': {'content': text},
      },
    ],
  }),
);

final _url = Uri.parse('https://api.example.com/v1/chat/completions');

void main() {
  test('the text of the stream arrives in the reply', () async {
    final fake = FakeSseClient(
      (request) => FakeSseResponse.events([
        _delta('Hel'),
        _delta('lo **you**'),
        const SseEvent('[DONE]'),
      ]),
    );
    final chat = LlmChatController.sse(
      url: _url,
      headers: {'Authorization': 'Bearer test-key'},
      body: SseChatBackend.openAIBody(
        model: 'test-model',
        system: 'Be brief',
        extra: {'temperature': 0},
      ),
      client: fake,
      history: [ChatMessage.user('Hi'), ChatMessage.assistant('Hello!')],
    );
    addTearDown(chat.dispose);

    await chat.send('How are you?');
    expect(chat.messages.last.text, 'Hello **you**');
    expect(chat.messages.last.reply!.isComplete, isTrue);
    expect(chat.messages.last.hasError, isFalse);
    expect(chat.isReplying, isFalse);

    final request = fake.requests.single;
    expect(request.method, 'POST');
    expect(request.url, _url);
    expect(request.headers['Authorization'], 'Bearer test-key');
    expect(jsonDecode(fake.bodies.single), {
      'model': 'test-model',
      'stream': true,
      'messages': [
        {'role': 'system', 'content': 'Be brief'},
        {'role': 'user', 'content': 'Hi'},
        {'role': 'assistant', 'content': 'Hello!'},
        {'role': 'user', 'content': 'How are you?'},
      ],
      'temperature': 0,
    });
    expect(fake.aborted, 0);
  });

  test('the error body of the API is the reply\'s error', () async {
    final fake = FakeSseClient(
      (request) => FakeSseResponse.error(
        401,
        '{"error": {"message": "Invalid API key", "type": "auth"}}',
      ),
    );
    final chat = LlmChatController.sse(
      url: _url,
      body: SseChatBackend.openAIBody(model: 'm'),
      client: fake,
    );
    addTearDown(chat.dispose);

    await chat.send('Hi');
    final reply = chat.messages.last.reply!;
    expect(reply.isComplete, isTrue);
    final error = reply.error;
    expect(error, isA<SseException>());
    expect((error! as SseException).statusCode, 401);
    expect(chatErrorText(error), 'Invalid API key');
    expect(chat.isReplying, isFalse);
    expect(chat.canRetry, isTrue);
  });

  test('an error event in the stream keeps the text so far', () async {
    final fake = FakeSseClient(
      (request) => FakeSseResponse.events([
        _delta('Half'),
        const SseEvent('{"error": {"message": "Overloaded"}}'),
      ]),
    );
    final chat = LlmChatController.sse(
      url: _url,
      body: SseChatBackend.openAIBody(model: 'm'),
      client: fake,
    );
    addTearDown(chat.dispose);
    await chat.send('Hi');
    expect(chat.messages.last.text, 'Half');
    expect(chatErrorText(chat.messages.last.reply!.error!), 'Overloaded');
  });

  test('stop aborts the request', () async {
    final fake = FakeSseClient(
      (request) =>
          FakeSseResponse.events([_delta('Once upon')], keepOpen: true),
    );
    final chat = LlmChatController.sse(
      url: _url,
      body: SseChatBackend.openAIBody(model: 'm'),
      client: fake,
    );
    addTearDown(chat.dispose);

    final sending = chat.send('Tell a story');
    final reply = chat.messages.last.reply!;
    final arrived = Completer<void>();
    reply.addListener(() {
      if (reply.text.isNotEmpty && !arrived.isCompleted) arrived.complete();
    });
    await arrived.future.timeout(const Duration(seconds: 5));
    expect(chat.isReplying, isTrue);
    expect(fake.aborted, 0);

    chat.stop();
    await sending.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    expect(fake.aborted, 1);
    expect(chat.isReplying, isFalse);
    expect(reply.text, 'Once upon');
    expect(reply.error, isNull);
  });

  test('the body builder gets the prompt with its attachments, and another '
      'API can be read', () async {
    late List<ChatMessage> seen;
    final fake = FakeSseClient(
      (request) => FakeSseResponse.events([
        const SseEvent(
          '{"type": "content_block_delta", '
          '"delta": {"type": "text_delta", "text": "Bonjour"}}',
          event: 'content_block_delta',
        ),
        const SseEvent('{}', event: 'message_stop'),
      ]),
    );
    final chat = LlmChatController.sse(
      url: _url,
      body: (messages) async {
        seen = messages;
        return {'n': messages.length};
      },
      text: (events) => events.anthropicText(),
      client: fake,
    );
    addTearDown(chat.dispose);
    const file = ChatAttachment(name: 'notes.txt');
    await chat.send('Translate', attachments: [file]);
    expect(seen.single.text, 'Translate');
    expect(seen.single.attachments, [file]);
    expect(jsonDecode(fake.bodies.single), {'n': 1});
    expect(chat.messages.last.text, 'Bonjour');
  });

  test('SseChatBackend works as an onReply', () async {
    final fake = FakeSseClient(
      (request) =>
          FakeSseResponse.events([_delta('Yes'), const SseEvent('[DONE]')]),
    );
    final backend = SseChatBackend(
      url: _url,
      body: SseChatBackend.openAIBody(model: 'm'),
      method: 'PUT',
      client: fake,
    );
    final chat = LlmChatController(onReply: backend.call);
    addTearDown(chat.dispose);
    await chat.send('Really?');
    expect(chat.messages.last.text, 'Yes');
    expect(fake.requests.single.method, 'PUT');
    expect((jsonDecode(fake.bodies.single) as Map)['messages'], [
      {'role': 'user', 'content': 'Really?'},
    ]);
  });

  test('chatErrorText reads the usual error shapes', () {
    expect(
      chatErrorText(const SseException('HTTP 500', body: '{"error": "Down"}')),
      'Down',
    );
    expect(
      chatErrorText(const SseException('HTTP 400', body: '{"message": "Bad"}')),
      'Bad',
    );
    expect(
      chatErrorText(const SseException('HTTP 502', body: ' <html>gateway ')),
      '<html>gateway',
    );
    expect(
      chatErrorText(const SseException('HTTP 400', body: '{"code": 3}')),
      '{"code": 3}',
    );
    expect(chatErrorText(const SseException('No answer')), 'No answer');
    expect(chatErrorText(Exception('offline')), 'offline');
    expect(chatErrorText(StateError('odd')), 'Bad state: odd');
  });
}
