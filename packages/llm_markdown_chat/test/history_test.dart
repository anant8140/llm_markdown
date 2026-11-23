import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_chat/llm_markdown_chat.dart';

void main() {
  group('regenerate', () {
    test('replaces the reply, asking with the same user message', () async {
      final prompts = <String>[];
      final histories = <List<String>>[];
      var count = 0;
      final chat = LlmChatController(
        onReply: (prompt, reply, history) async {
          prompts.add(prompt);
          histories.add([for (final m in history) m.text]);
          reply.append('Answer ${++count}');
        },
      );
      addTearDown(chat.dispose);
      await chat.send('One');
      await chat.send('Two');
      final first = chat.messages[1];
      final last = chat.messages[3];
      expect(chat.canRegenerate(last), isTrue);
      expect(chat.canRegenerate(chat.messages[2]), isFalse);

      await chat.regenerate(last);
      expect(prompts, ['One', 'Two', 'Two']);
      expect(histories.last, ['One', 'Answer 1']);
      expect(
        [for (final m in chat.messages) m.text],
        ['One', 'Answer 1', 'Two', 'Answer 3'],
      );
      expect(chat.messages.contains(last), isFalse);

      // an earlier reply: what came after it goes too
      await chat.regenerate(first);
      expect(prompts.last, 'One');
      expect(histories.last, isEmpty);
      expect([for (final m in chat.messages) m.text], ['One', 'Answer 4']);
    });

    test('does nothing for a foreign message or while replying', () async {
      final gate = Completer<void>();
      var calls = 0;
      final chat = LlmChatController(
        history: [ChatMessage.user('Q'), ChatMessage.assistant('A')],
        onReply: (prompt, reply, history) {
          calls++;
          return gate.future;
        },
      );
      addTearDown(chat.dispose);
      await chat.regenerate(ChatMessage.assistant('Other'));
      expect(calls, 0);
      final old = chat.messages[1];
      final sending = chat.send('Next');
      expect(chat.canRegenerate(old), isFalse);
      await chat.regenerate(old);
      expect(calls, 1);
      expect(chat.messages.length, 4);
      gate.complete();
      await sending;
    });

    test('keeps the attachments of the prompt', () async {
      final chat = LlmChatController(
        onReply: (prompt, reply, history) async => reply.append('ok'),
      );
      addTearDown(chat.dispose);
      const file = ChatAttachment(name: 'a.txt', uri: '/tmp/a.txt');
      await chat.send('See', attachments: [file]);
      await chat.retry();
      expect(chat.messages.length, 2);
      expect(chat.messages.first.attachments, [file]);
    });
  });

  group('edit', () {
    test('replaces the message and everything after it', () async {
      final prompts = <String>[];
      final histories = <List<String>>[];
      final chat = LlmChatController(
        onReply: (prompt, reply, history) async {
          prompts.add(prompt);
          histories.add([for (final m in history) m.text]);
          reply.append('Re: $prompt');
        },
      );
      addTearDown(chat.dispose);
      await chat.send('One');
      await chat.send('Two');
      await chat.send('Three');
      final second = chat.messages[2];
      expect(chat.canEdit(second), isTrue);
      expect(chat.canEdit(chat.messages[3]), isFalse);

      await chat.edit(second, 'Two, changed');
      expect(
        [for (final m in chat.messages) m.text],
        ['One', 'Re: One', 'Two, changed', 'Re: Two, changed'],
      );
      expect(prompts.last, 'Two, changed');
      expect(histories.last, ['One', 'Re: One']);
      expect(chat.messages.contains(second), isFalse);

      // not for an empty text, a removed message or a reply
      await chat.edit(chat.messages[0], '   ');
      await chat.edit(second, 'Gone');
      await chat.edit(chat.messages[1], 'Reply');
      expect(chat.messages.length, 4);
      expect(prompts.length, 4);
    });

    test('keeps or replaces the attachments', () async {
      final chat = LlmChatController(
        onReply: (prompt, reply, history) async => reply.append('ok'),
      );
      addTearDown(chat.dispose);
      const a = ChatAttachment(name: 'a');
      const b = ChatAttachment(name: 'b');
      await chat.send('One', attachments: [a]);
      await chat.edit(chat.messages.first, 'Two');
      expect(chat.messages.first.attachments, [a]);
      await chat.edit(chat.messages.first, 'Three', attachments: [b]);
      expect(chat.messages.first.attachments, [b]);
      expect(chat.messages.first.text, 'Three');
    });
  });

  group('attachments', () {
    test('reach the sent message and onReply', () async {
      late LlmChatController chat;
      ChatMessage? answered;
      chat = LlmChatController(
        onReply: (prompt, reply, history) async {
          answered = chat.lastUserMessage;
          reply.append('ok');
        },
      );
      addTearDown(chat.dispose);
      expect(chat.lastUserMessage, isNull);
      final file = ChatAttachment(
        name: 'photo.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      // attachments alone are enough to send
      await chat.send('', attachments: [file]);
      expect(chat.messages.length, 2);
      expect(chat.messages.first.attachments.single, same(file));
      expect(answered, same(chat.messages.first));
      expect(chat.messages.last.attachments, isEmpty);
      expect(
        () => chat.messages.first.attachments.add(file),
        throwsUnsupportedError,
      );
    });
  });

  group('JSON', () {
    test('a chat comes back the same', () async {
      final chat = LlmChatController(
        onReply: (prompt, reply, history) async {
          if (prompt == 'fail') throw Exception('offline');
          reply
            ..appendThinking('Let me think')
            ..append('**Paris** [1]')
            ..addSource(
              const MarkdownSource(
                url: 'https://example.com',
                title: 'Example',
                citedText: 'Paris is the capital',
              ),
            );
        },
      );
      addTearDown(chat.dispose);
      await chat.send(
        'Capital of France?',
        attachments: [
          ChatAttachment(
            name: 'map.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList([0, 255, 7]),
            uri: 'file:///map.png',
          ),
        ],
      );
      await chat.send('fail');

      final json = chat.toJson();
      expect(json['version'], 1);
      // through text, as an app would store it
      final restored = LlmChatController.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
        onReply: (prompt, reply, history) async {},
      );
      addTearDown(restored.dispose);

      expect(restored.messages.length, 4);
      for (var i = 0; i < 4; i++) {
        final before = chat.messages[i];
        final after = restored.messages[i];
        expect(after.id, before.id);
        expect(after.role, before.role);
        expect(after.text, before.text);
        expect(after.createdAt, isNotNull);
        expect(after.createdAt!.isAtSameMomentAs(before.createdAt!), isTrue);
      }
      final file = restored.messages[0].attachments.single;
      expect(file.name, 'map.png');
      expect(file.mimeType, 'image/png');
      expect(file.bytes, [0, 255, 7]);
      expect(file.uri, 'file:///map.png');

      final reply = restored.messages[1].reply!;
      expect(reply.isComplete, isTrue);
      expect(reply.error, isNull);
      expect(reply.thinking, 'Let me think');
      expect(reply.sources, chat.messages[1].reply!.sources);
      expect(reply.sources.single.citedText, 'Paris is the capital');

      final failed = restored.messages[3];
      expect(failed.reply!.isComplete, isTrue);
      expect(failed.hasError, isTrue);
      expect('${failed.reply!.error}', contains('offline'));

      // saved again it is the same JSON
      expect(jsonEncode(restored.toJson()), jsonEncode(json));
    });

    test('thinking, sources and bytes can be left out', () async {
      final chat = LlmChatController(
        onReply: (prompt, reply, history) async {
          reply
            ..appendThinking('Hm')
            ..append('Text')
            ..addSource(const MarkdownSource(url: 'https://a.example'));
        },
      );
      addTearDown(chat.dispose);
      await chat.send(
        'Q',
        attachments: [
          ChatAttachment(name: 'f', bytes: Uint8List.fromList([1])),
        ],
      );
      final full = chat.toJson()['messages']! as List;
      expect((full[1] as Map).keys, containsAll(['thinking', 'sources']));
      expect(((full[0] as Map)['attachments'] as List).single, {
        'name': 'f',
        'bytes': 'AQ==',
      });

      final small =
          chat.toJson(
                thinking: false,
                sources: false,
                attachmentBytes: false,
              )['messages']!
              as List;
      expect((small[1] as Map).containsKey('thinking'), isFalse);
      expect((small[1] as Map).containsKey('sources'), isFalse);
      expect(((small[0] as Map)['attachments'] as List).single, {'name': 'f'});
    });

    test('the written shape is stable, and odd input is survived', () {
      final chat = LlmChatController(
        history: [
          ChatMessage.user('Hi', id: 'u1'),
          ChatMessage.assistant('Hello', id: 'a1'),
        ],
        onReply: (prompt, reply, history) async {},
      );
      addTearDown(chat.dispose);
      expect(chat.toJson(), {
        'version': 1,
        'messages': [
          {'id': 'u1', 'role': 'user', 'text': 'Hi'},
          {'id': 'a1', 'role': 'assistant', 'text': 'Hello'},
        ],
      });

      final odd = LlmChatController.fromJson({
        'version': 7,
        'later': true,
        'messages': [
          'not a message',
          {'role': 'user', 'text': 'Kept', 'time': 'never', 'extra': 1},
          {'role': 'assistant', 'text': 5, 'sources': 'none'},
        ],
      }, onReply: (prompt, reply, history) async {});
      addTearDown(odd.dispose);
      expect(odd.messages.length, 2);
      expect(odd.messages[0].text, 'Kept');
      expect(odd.messages[0].createdAt, isNull);
      expect(odd.messages[0].id, isNotEmpty);
      expect(odd.messages[1].role, ChatRole.assistant);
      expect(odd.messages[1].text, '');
      expect(odd.messages[1].reply!.isComplete, isTrue);

      final empty = LlmChatController.fromJson(
        const {},
        onReply: (prompt, reply, history) async {},
      );
      addTearDown(empty.dispose);
      expect(empty.messages, isEmpty);
    });

    test('new messages get ids unlike the restored ones', () async {
      final chat = LlmChatController.fromJson({
        'version': 1,
        'messages': [
          {'id': 'message_0', 'role': 'user', 'text': 'Q'},
          {'id': 'message_1', 'role': 'assistant', 'text': 'A'},
        ],
      }, onReply: (prompt, reply, history) async => reply.append('B'));
      addTearDown(chat.dispose);
      await chat.send('More');
      final ids = {for (final m in chat.messages) m.id};
      expect(ids.length, 4);
    });
  });
}
