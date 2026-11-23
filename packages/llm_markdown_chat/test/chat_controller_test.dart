import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_markdown/llm_markdown.dart';
import 'package:llm_markdown_chat/llm_markdown_chat.dart';

void main() {
  test('send adds the prompt and a streamed reply', () async {
    final calls = <(String, List<String>)>[];
    final chat = LlmChatController(
      history: [ChatMessage.user('Hi'), ChatMessage.assistant('Hello!')],
      onReply: (prompt, reply, history) async {
        calls.add((prompt, [for (final m in history) m.text]));
        reply.append('**Sure**');
      },
    );
    addTearDown(chat.dispose);
    var notified = 0;
    chat.addListener(() => notified++);

    final sending = chat.send('  Tell me  ');
    expect(chat.isReplying, isTrue);
    expect(chat.messages.map((m) => m.role), [
      ChatRole.user,
      ChatRole.assistant,
      ChatRole.user,
      ChatRole.assistant,
    ]);
    expect(chat.messages[2].text, 'Tell me');
    await sending;

    expect(calls.single.$1, 'Tell me');
    expect(calls.single.$2, ['Hi', 'Hello!']);
    expect(chat.isReplying, isFalse);
    expect(chat.messages.last.text, '**Sure**');
    expect(chat.messages.last.reply!.isComplete, isTrue);
    expect(chat.messages.first.reply, isNull);
    expect(chat.messages[1].reply!.isComplete, isTrue);
    expect(notified, 2);
    expect(chat.canRetry, isTrue);
  });

  test('empty prompts and prompts while replying are ignored', () async {
    final gate = Completer<void>();
    var calls = 0;
    final chat = LlmChatController(
      onReply: (prompt, reply, history) {
        calls++;
        return gate.future;
      },
    );
    addTearDown(chat.dispose);
    await chat.send('   ');
    expect(chat.messages, isEmpty);
    final first = chat.send('One');
    await chat.send('Two');
    expect(calls, 1);
    expect(chat.messages.length, 2);
    expect(chat.canRetry, isFalse);
    gate.complete();
    await first;
  });

  test('an error ends the reply with it, and retry asks again', () async {
    var attempt = 0;
    final chat = LlmChatController(
      onReply: (prompt, reply, history) async {
        attempt++;
        if (attempt == 1) {
          reply.append('Part');
          throw StateError('offline');
        }
        reply.append('Answer to $prompt after ${history.length}');
      },
    );
    addTearDown(chat.dispose);
    await chat.send('Q');
    expect(chat.messages.last.hasError, isTrue);
    expect('${chat.messages.last.reply!.error}', contains('offline'));
    expect(chat.messages.last.text, 'Part');
    expect(chat.isReplying, isFalse);
    expect(chat.canRetry, isTrue);

    await chat.retry();
    expect(chat.messages.length, 2);
    expect(chat.messages.first.text, 'Q');
    expect(chat.messages.last.text, 'Answer to Q after 0');
    expect(chat.messages.last.hasError, isFalse);
  });

  test('stop ends the reply at once and lets a new prompt in', () async {
    final source = StreamController<String>();
    var cancelled = false;
    source.onCancel = () => cancelled = true;
    final chat = LlmChatController(
      onReply: (prompt, reply, history) async {
        if (prompt == 'slow') return reply.addStream(source.stream);
        reply.append('quick');
      },
    );
    addTearDown(chat.dispose);
    final slow = chat.send('slow');
    source.add('Some ');
    await Future<void>.delayed(Duration.zero);
    expect(chat.messages.last.text, 'Some ');
    chat.stop();
    expect(chat.isReplying, isFalse);
    expect(chat.messages.last.reply!.isComplete, isTrue);
    expect(chat.messages.last.hasError, isFalse);
    await slow;
    expect(cancelled, isTrue);
    expect(chat.canRetry, isTrue);

    await chat.send('fast');
    expect(chat.messages.last.text, 'quick');
    expect(chat.messages.length, 4);
    await source.close();
  });

  test('clear removes everything and a late reply writes nowhere', () async {
    final gate = Completer<void>();
    late StreamingMarkdownController late;
    final chat = LlmChatController(
      onReply: (prompt, reply, history) async {
        late = reply;
        await gate.future;
        throw StateError('too late');
      },
    );
    addTearDown(chat.dispose);
    final sending = chat.send('Q');
    chat.clear();
    expect(chat.messages, isEmpty);
    expect(chat.isReplying, isFalse);
    gate.complete();
    await sending;
    expect(late.error, isNull);
    expect(chat.canRetry, isFalse);
  });

  test('dispose ends a running reply without errors', () async {
    final gate = Completer<void>();
    final chat = LlmChatController(
      onReply: (prompt, reply, history) => gate.future,
    );
    final sending = chat.send('Q');
    chat.dispose();
    gate.complete();
    await sending;
  });

  test('no retry when the history ends with a prompt', () async {
    final chat = LlmChatController(
      history: [ChatMessage.user('A'), ChatMessage.user('B')],
      onReply: (prompt, reply, history) async {},
    );
    addTearDown(chat.dispose);
    expect(chat.canRetry, isFalse);
    await chat.retry();
    expect(chat.messages.map((m) => m.text), ['A', 'B']);
  });

  test('message ids are distinct', () {
    final a = ChatMessage.user('x');
    final b = ChatMessage.user('x');
    expect(a.id, isNot(b.id));
    expect(ChatMessage.user('x', id: 'mine').id, 'mine');
  });

  test('history leaves out failed and empty turns', () async {
    final seen = <List<String>>[];
    var attempt = 0;
    final source = StreamController<String>();
    final chat = LlmChatController(
      history: [ChatMessage.user('Old'), ChatMessage.assistant('Fine')],
      onReply: (prompt, reply, history) async {
        seen.add([for (final m in history) '${m.role.name}:${m.text}']);
        attempt++;
        if (attempt == 1) throw StateError('down');
        if (attempt == 2) return reply.addStream(source.stream);
        reply.append('ok');
      },
    );
    addTearDown(chat.dispose);
    await chat.send('Fails');
    final stopped = chat.send('Stopped');
    await Future<void>.delayed(Duration.zero);
    chat.stop();
    await stopped;
    await chat.send('Last');
    expect(seen.last, ['user:Old', 'assistant:Fine']);
    // all six messages are still shown
    expect(chat.messages.length, 8);
    await source.close();
  });

  test('a stopped reply with text stays in the history', () async {
    final seen = <List<String>>[];
    final source = StreamController<String>();
    final chat = LlmChatController(
      onReply: (prompt, reply, history) async {
        seen.add([for (final m in history) m.text]);
        if (prompt == 'A') return reply.addStream(source.stream);
      },
    );
    addTearDown(chat.dispose);
    final first = chat.send('A');
    source.add('Partial');
    await Future<void>.delayed(Duration.zero);
    chat.stop();
    await first;
    await chat.send('B');
    expect(seen.last, ['A', 'Partial']);
    await source.close();
  });

  test('stopping while the request is sent ends quietly', () async {
    final sent = Completer<void>();
    var cancelled = false;
    final chat = LlmChatController(
      onReply: (prompt, reply, history) async {
        await sent.future;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        await reply.addOpenAIStream(body.stream);
      },
    );
    addTearDown(chat.dispose);
    final sending = chat.send('Q');
    chat.stop();
    sent.complete();
    await sending;
    expect(cancelled, isTrue);
    expect(chat.messages.last.hasError, isFalse);
  });

  test('send, stop and clear after dispose do nothing', () async {
    final chat = LlmChatController(onReply: (p, r, h) async {});
    chat.dispose();
    await chat.send('Q');
    chat.stop();
    chat.clear();
    expect(chat.messages, isEmpty);
  });
}
